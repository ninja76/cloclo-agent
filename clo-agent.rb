#! /usr/bin/env ruby
# Clo-Clo Linux agent
# Reports back basic system information
#

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'rest-client'
require 'json'
require 'rufus-scheduler'
require 'yaml'

scheduler = Rufus::Scheduler.new

def get_cpu_stats
    File.open("/proc/stat", "r").each_line do |line|
      info = line.split(/\s+/)
      name = info.shift
      return info.map{|i| i.to_f} if name.match(/^cpu$/)
    end
  end

  def get_cpu_metrics
    metrics = [:user, :nice, :system, :idle, :iowait, :irq, :softirq, :steal, :guest]

    cpu_stats_before = get_cpu_stats
    sleep 2
    cpu_stats_after = get_cpu_stats

    # Some kernels don't have a 'guest' value (RHEL5).
    metrics = metrics.slice(0, cpu_stats_after.length)

    cpu_total_diff = 0.to_f
    cpu_stats_diff = []
    metrics.each_index do |i|
      cpu_stats_diff[i] = cpu_stats_after[i] - cpu_stats_before[i]
      cpu_total_diff += cpu_stats_diff[i]
    end

    cpu_stats = []
    metrics.each_index do |i|
      cpu_stats[i] = 100*(cpu_stats_diff[i]/cpu_total_diff)
    end

    cpu_usage = 100*(cpu_total_diff - cpu_stats_diff[3])/cpu_total_diff
    checked_usage = cpu_usage

    metrics.each do |metric|
      checked_usage = cpu_stats[metrics.find_index(metric)]
    end

    msg = "cpu_total=#{cpu_usage.round(2)}"
    cpu_stats.each_index {|i| msg += " #{metrics[i]}=#{cpu_stats[i].round(2)}"}
    return msg
  end

  def get_memory_pct
    total_ram, free_ram = 0, 0
      `free -m`.split("\n").drop(1).each do |line|
      free_ram = line.split[3].to_i if line =~ /^-\/\+ buffers\/cache:/
      total_ram = line.split[1].to_i if line =~ /^Mem:/
    end
    return free_ram*100/total_ram
  end

def read_config
  if  File.exist?('clo-agent.yaml')
    config = YAML.load_file("clo-agent.yaml")
    return config
  else 
    abort("clo-agent.yaml not found")
  end
end

config = read_config

scheduler.every '60s' do
  puts "starting send"
  percents_left = get_memory_pct
  web_connections = `netstat -anp | grep nginx | grep ESTABLISHED | wc -l`
  cpu_total = get_cpu_metrics.split(' ')[0].split('=')[1]

  jdata = {:key => config["config"]["key"], 
           :node => config["config"]["node"], 
           :ram_usage => "#{percents_left}", 
           :cpu_total => "#{cpu_total}", 
           :http_conn => "#{web_connections.chop}"}
  puts "sending #{jdata}"
  RestClient.put "http://www.clo-clo.net/streams", jdata.to_json, {:content_type => :json}
end
scheduler.join
