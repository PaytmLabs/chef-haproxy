#
# Cookbook Name:: haproxy
# Recipe:: manual
#
# Copyright 2014, Heavy Water Operations, LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "haproxy::install_#{node['haproxy']['install_method']}"

cookbook_file "/etc/default/haproxy" do
  source "haproxy-default"
  owner "root"
  group "root"
  mode 00644
  notifies :restart, "service[haproxy]", :delayed
end


if node['haproxy']['enable_admin']
  admin = node['haproxy']['admin']
  haproxy_lb "admin" do
    bind "#{admin['address_bind']}:#{admin['port']}"
    mode 'http'
    params(admin['options'])
  end
end

conf = node['haproxy']
member_max_conn = conf['member_max_connections']
member_weight = conf['member_weight']

if conf['enable_default_http']
  haproxy_lb 'http' do
    type 'frontend'
    params({
      'maxconn' => conf['frontend_max_connections'],
      'bind' => "#{conf['incoming_address']}:#{conf['incoming_port']}",
      'default_backend' => 'servers-http'
    })
  end

  member_port = conf['member_port']
  pool = []
  pool << "option httpchk #{conf['httpchk']}" if conf['httpchk']
  pool << "cookie #{node['haproxy']['cookie']}" if node['haproxy']['cookie']
  servers = node['haproxy']['members'].map do |member|
    "#{member['hostname']} #{member['ipaddress']}:#{member['port'] || member_port} weight #{member['weight'] || member_weight} maxconn #{member['max_connections'] || member_max_conn} check #{node['haproxy']['pool_members_option']}" 
  end
  haproxy_lb "servers-http" do
    type 'backend'
    servers servers
    params pool
  end
end


if node['haproxy']['enable_ssl']
  if node['haproxy']['ssl_crt_path']
    bind = "#{node['haproxy']['ssl_incoming_address']}:#{node['haproxy']['ssl_incoming_port']} ssl crt #{node['haproxy']['ssl_crt_path']}"
  else
    bind = "#{node['haproxy']['ssl_incoming_address']}:#{node['haproxy']['ssl_incoming_port']}"
  end
  
  haproxy_lb 'https' do
    type 'frontend'
    mode node['haproxy']['ssl_mode']
    params({
      'maxconn' => node['haproxy']['frontend_ssl_max_connections'],
      'bind' => bind,
      'default_backend' => 'servers-https'
    })
  end

  ssl_member_port = conf['ssl_member_port']
  pool = ['option ssl-hello-chk']
  pool << "option httpchk #{conf['ssl_httpchk']}" if conf['ssl_httpchk']
  pool << "cookie #{node['haproxy']['cookie']}" if node['haproxy']['cookie']
  servers = node['haproxy']['members'].map do |member|
    "#{member['hostname']} #{member['ipaddress']}:#{member['ssl_port'] || ssl_member_port} weight #{member['weight'] || member_weight} maxconn #{member['max_connections'] || member_max_conn} check #{node['haproxy']['pool_members_option']}"
  end
  haproxy_lb "servers-https" do
    type 'backend'
    mode node['haproxy']['ssl_mode']
    servers servers
    params pool
  end
end

# Re-default user/group to account for role/recipe overrides
node.default['haproxy']['stats_socket_user'] = node['haproxy']['user']
node.default['haproxy']['stats_socket_group'] = node['haproxy']['group']


unless node['haproxy']['global_options'].is_a?(Hash)
  Chef::Log.error("Global options needs to be a Hash of the format: { 'option' => 'value' }. Please set node['haproxy']['global_options'] accordingly.")
end

haproxy_config "Create haproxy.cfg" do
  notifies :restart, "service[haproxy]", :delayed
end
