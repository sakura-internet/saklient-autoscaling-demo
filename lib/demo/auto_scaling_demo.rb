require 'saklient/cloud/api'
require 'ipaddr'
require 'yaml'

# Autoscaling demo.
# @author SAKURA Internet Inc.
# @see https://github.com/sakura-internet/saklient-autoscaling-demo
class AutoScalingDemo
  def initialize
    @config            = YAML.load_file(File.expand_path('../../../config/config.yml', __FILE__))
    @api               = Saklient::Cloud::API.authorize(@config['token'], @config['secret'], @config['zone'])
    @tag               = 'autoscaling-demo'
    @min_servers_count = 1
    @max_servers_count = 5
    @monitor_interval  = 300 # seconds
    @cpu_time_scale_out_threshold = 0.4
    @cpu_time_scale_in_threshold  = 0.2
  end

  def run
    resources = setup
    monitor(resources)
  end

  def setup
    # search servers
    puts 'searching servers'
    servers = @api.server
                  .with_tag(@tag)
                  .find

    # search base server
    puts 'searching base server'
    base_server = @api.server.get_by_id(@config['base_server_id'])

    servers = servers.reject { |s| s.id == base_server.id }
    servers.unshift(base_server)

    # search source disk
    puts 'searching source disk'
    source_disk = base_server.find_disks[0]

    # search swytch
    puts 'searching swytch'
    swytch = @api.swytch.get_by_id(@config['swytch_id'])

    router = swytch.router
    net    = swytch.ipv4_nets[0]

    # search loadbalancer
    puts 'searching loadbalancer'
    lb = @api.appliance.get_by_id(@config['lb_id'].to_s)

    {
      servers: servers,
      source_disk: source_disk,
      router: router,
      swytch: swytch,
      net: net,
      lb: lb
    }
  end

  def monitor(resources)
    servers = resources[:servers]

    puts "[monitor][#{now_string}] ***** start *****"
    loop do
      ave_cpu_time = average_cpu_time(servers)

      if ave_cpu_time.nil?
        sleep(@monitor_interval)
        next
      end

      if ave_cpu_time > @cpu_time_scale_out_threshold && servers.size < @max_servers_count
        puts "[monitor][#{now_string}] << scale out start >>"
        add_server(resources)
        puts "[monitor][#{now_string}] << scale out end >>"
      elsif ave_cpu_time < @cpu_time_scale_in_threshold && servers.size > @min_servers_count
        puts "[monitor][#{now_string}] >> scale in start <<"
        remove_server(resources)
        puts "[monitor][#{now_string}] >> scale in end <<"
      end

      sleep(@monitor_interval)
    end
    puts "[monitor][#{now_string}] ***** end *****"
  end

  def average_cpu_time(servers)
    cpu_times = []

    servers.each do |server|
      samples = server.activity.fetch.samples

      index = samples.size - 1
      latest = nil
      until samples[index].nil?
        if samples[index].is_available
          latest = samples[index]
          break
        end
        index -= 1
      end
      cpu_times << latest.cpu_time unless latest.nil?
    end

    puts "[monitor][#{now_string}] cpu_times => #{cpu_times}"

    return nil unless cpu_times.size == servers.size

    sum_time = cpu_times.reduce { |a, e| a + e }
    ave_time = sum_time / servers.size

    puts "[monitor][#{now_string}] sum_time => #{sum_time}"
    puts "[monitor][#{now_string}] ave_time => #{ave_time}"

    ave_time
  end

  def add_server(resources)
    ipaddresses = resources[:swytch].collect_unused_ipv4_addresses
    if ipaddresses.empty?
      puts '[ERROR] There are no practicable IP addresses.'
      return
    end

    # collect_unused_ipv4_addressesで取得される配列にVIPが含まれているので除外
    ipaddresses.delete(resources[:lb].virtual_ips[0].virtual_ip_address)

    # duplicate a server
    new_server = resources[:servers][0].easy_duplicate(ipaddresses[0], true)
    new_server.boot

    # add a server to loadbalancer
    puts 'add a server to loadbalancer'
    lb     = resources[:lb]
    lb_vip = lb.virtual_ips[0]
    lb_vip.add_server(ip: ipaddresses[0], port: 80, protocol: 'ping', enabled: 'true')
    lb.save
    lb.apply

    resources[:servers] << new_server
  end

  def remove_server(resources)
    server = resources[:servers].pop
    lb     = resources[:lb]

    # remove a server
    puts 'removing a server'
    server.shutdown
    unless server.sleep_until_down
      server.stop
      server.sleep_until_down || raise
    end

    disks = server.find_disks
    disks.each do |disk|
      disk.disconnect
      disk.destroy
    end

    # remove a lb_server
    puts 'removing a lb_server'
    lb_vip = lb.virtual_ips[0]
    lb_vip.remove_server_by_address(server.ifaces[0].user_ip_address)
    lb.save
    lb.reload

    server.destroy
  end

  def now_string
    Time.now.strftime('%Y-%m-%d %H:%M:%S')
  end
end
