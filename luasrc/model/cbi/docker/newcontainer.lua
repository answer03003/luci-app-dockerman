--[[
LuCI - Lua Configuration Interface
Copyright 2019 lisaac <lisaac.cn@gmail.com>
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
	http://www.apache.org/licenses/LICENSE-2.0
$Id$
]]--

require "luci.util"
local uci = luci.model.uci.cursor()
local docker = require "luci.model.docker"
local dk = docker.new()
local cmd_line = table.concat(arg, '/')
luci.util.perror(cmd_line)
local images = dk.images:list().body
local networks = dk.networks:list().body
local containers = dk.containers:list(nil, {all=true}).body
local default_config = { }
--docker run -dit --name test -v /media:/media:rslave alpine tail -f /dev/null
if cmd_line and cmd_line:match("^docker.+") then
  local key = nil
  --cursor = 0: docker run
  --cursor = 1: resloving para
  --cursor = 2: resloving image
  --cursor > 2: resloving command
  local cursor = 0
  for w in cmd_line:gmatch("[^%s]+") do 
    -- skip '\'
    if w == '\\' then
    -- start with '-'
    elseif w:match("^%-+(.+)") and cursor <= 1 then
      local v = w:match("^%-+.-=(.+)")
      if v then
        key = w:match("^%-+(.-)=.+"):lower()
      else
        key = w:match("^%-+(.+)"):lower()
      end
      if key == "v" or key == "volume" then
        key = "mount"
      elseif key == "p" then
        key = "port"
      elseif key == "e" then
        key = "env"
      elseif key == "net" then
        key = "network"
      elseif key == "cpu-shares" then
        key = "cpushares"
      elseif key == "m" then
        key = "memory"
      elseif key == "blkio-weight" then
        key = "blkioweight"
      elseif key == "privileged" then
        default_config["privileged"] = 1
      end
      if v then
        if key == "mount" or key == "link" or key == "env" or key == "port" or key == "device" or key == "tmpfs" then
          if not default_config[key] then default_config[key] = {} end
          table.insert( default_config[key], v )
        else
          default_config[key] = v
        end
      end
    -- value
    elseif key and type(key) == "string" then
      if key == "mount" or key == "link" or key == "env" or key == "port" or key == "device" or key == "tmpfs" then
        if not default_config[key] then default_config[key] = {} end
        table.insert( default_config[key], w )
      else
        default_config[key] = w
      end

      if key == "cpus" or key == "cpushare" or key == "memory" or key == "blkioweight" or key == "device" or key == "tmpfs" then
        default_config["advance"] = 1
      end
      key = nil
      cursor = 1
    --image and command
    elseif cursor >= 1 and  key == nil then
      if cursor == 1 then
        default_config["image"] = w
      elseif cursor > 1 then
        default_config["command"] = (default_config["command"] and (default_config["command"] .. " " )or "")  .. w
      end
      cursor = cursor + 1
    end
  end
end

local m = SimpleForm("docker", translate("Docker"))
m.tempalte = "cbi/xsimpleform"
m.redirect = luci.dispatcher.build_url("admin", "docker", "containers")
-- m.reset = false
-- m.submit = false
-- new Container

docker_status = m:section(SimpleSection)
docker_status.template="docker/apply_widget"
docker_status.err=nixio.fs.readfile(dk.options.status_path)
if docker_status then docker:clear_status() end

local s = m:section(SimpleSection, translate("New Container"))
s.addremove = true
s.anonymous = true

local d = s:option(DummyValue,"cmd_line","Resolv CLI")
d.rawhtml  = true
d.template = "docker/resolv_container"

d = s:option(Value, "name", translate("Container Name"))
d.rmempty = true
d.default = default_config.name or nil
d = s:option(Value, "image", translate("Docker Image"))
d.rmempty = true
d.default = default_config.image or nil

for _, v in ipairs (images) do
  if v.RepoTags then
    d:value(v.RepoTags[1], v.RepoTags[1])
  end
end
d = s:option(Flag, "privileged", translate("Privileged"))
d.rmempty = true
d.disabled = 0
d.enabled = 1
d.default = default_config.privileged or 0

d = s:option(ListValue, "restart", translate("Restart policy"))
d.rmempty = true

d:value("no", "No")
d:value("unless-stopped", "Unless stopped")
d:value("always", "Always")
d:value("on-failure", "On failure")
d.default = default_config.restart or "unless-stopped"

local d_network = s:option(ListValue, "network", translate("Networks"))
d_network.rmempty = true
d_network.default = default_config.network or "bridge"

local d_ip = s:option(Value, "ip", translate("IPv4 Address"))
d_ip.datatype="ip4addr"
d_ip:depends("network", "nil")
d_ip.default = default_config.ip or nil

d = s:option(DynamicList, "link", translate("Links with other containers"))
d.placeholder = "container_name:alias"
d.rmempty = true
d:depends("network", "bridge")
d.default = default_config.link or nil

d = s:option(DynamicList, "env", translate("Environmental Variable"))
d.placeholder = "TZ=Asia/Shanghai"
d.rmempty = true
d.default = default_config.env or nil

d = s:option(DynamicList, "mount", translate("Bind Mount"))
d.placeholder = "/media:/media:slave"
d.rmempty = true
d.default = default_config.mount or nil

local d_ports = s:option(DynamicList, "port", translate("Exposed Ports"))
d_ports.placeholder = "2200:22/tcp"
d_ports.rmempty = true
d_ports.default = default_config.port or nil

d = s:option(Value, "user", translate("User"))
d.placeholder = "1000:1000"
d.rmempty = true
d.default = default_config.user or nil

d = s:option(Value, "command", translate("Run command"))
d.placeholder = "/bin/sh init.sh"
d.rmempty = true
d.default = default_config.command or nil

d = s:option(Flag, "advance", translate("Advance"))
d.rmempty = true
d.disabled = 0
d.enabled = 1
d.default = default_config.advance or 0

d = s:option(Value, "cpus", translate("CPUs"), translate("Number of CPUs. Number is a fractional number. 0.000 means no limit."))
d.placeholder = "1.5"
d.rmempty = true
d:depends("advance", 1)
d.datatype="ufloat"
d.default = default_config.cpus or nil

d = s:option(Value, "cpushares", translate("CPU Shares Weight"), translate("CPU shares (relative weight, if 0 is set, the system will ignore the value and use the default of 1024."))
d.placeholder = "1024"
d.rmempty = true
d:depends("advance", 1)
d.datatype="uinteger"
d.default = default_config.cpushares or nil

d = s:option(Value, "memory", translate("Memory"), translate("Memory limit (format: <number>[<unit>]). Number is a positive integer. Unit can be one of b, k, m, or g. Minimum is 4M."))
d.placeholder = "128m"
d.rmempty = true
d:depends("advance", 1)
d.default = default_config.memory or nil

d = s:option(Value, "blkioweight", translate("Block IO Weight"), translate("Block IO weight (relative weight) accepts a weight value between 10 and 1000."))
d.placeholder = "500"
d.rmempty = true
d:depends("advance", 1)
d.datatype="uinteger"
d.default = default_config.blkioweight or nil

d = s:option(DynamicList, "device", translate("Device"))
d.placeholder = "/dev/sda:/dev/xvdc:rwm"
d.rmempty = true
d:depends("advance", 1)
d.default = default_config.device or nil

d = s:option(DynamicList, "tmpfs", translate("Tmpfs"), translate("Mount tmpfs filesystems"))
d.placeholder = "/run:rw,noexec,nosuid,size=65536k"
d.rmempty = true
d:depends("advance", 1)
d.default = default_config.tmpfs or nil

for _, v in ipairs (networks) do
  if v.Name then
    local parent = v.Options and v.Options.parent or nil
    local ip = v.IPAM and v.IPAM.Config and v.IPAM.Config[1] and v.IPAM.Config[1].Subnet or nil
    ipv6 =  v.IPAM and v.IPAM.Config and v.IPAM.Config[2] and v.IPAM.Config[2].Subnet or nil
    local network_name = v.Name .. " | " .. v.Driver  .. (parent and (" | " .. parent) or "") .. (ip and (" | " .. ip) or "").. (ipv6 and (" | " .. ipv6) or "")
    d_network:value(v.Name, network_name)

    if v.Name ~= "none" and v.Name ~= "bridge" and v.Name ~= "host" then
      d_ip:depends("network", v.Name)
    end

    if v.Driver == "bridge" then
      d_ports:depends("network", v.Name)
    end
  end
end

m.handle = function(self, state, data)
  if state == FORM_VALID then
    local tmp
    local name = data.name
    local image = data.image
    local user = data.user
    if not image:match(".-:.+") then
      image = image .. ":latest"
    end
    local privileged = data.privileged
    local restart = data.restart
    local env = data.env
    local network = data.network
    local ip = (network ~= "bridge" and network ~= "host" and network ~= "none") and data.ip or nil
    local mount = data.mount
    local memory = data.memory or 0
    local cpushares = data.cpushares or 0
    local cpus = data.cpus or 0
    local blkioweight = data.blkioweight or 500

    local portbindings = {}
    local exposedports = {}
    local tmpfs = {}
    tmp = data.tmpfs
    if type(tmp) == "table" then
      for i, v in ipairs(tmp)do
        local _,_, k,v1 = v:find("(.-):(.+)")
        if k and v1 then
          tmpfs[k]=v1
        end
      end
    end

    local device = {}
    tmp = data.device
    if type(tmp) == "table" then
      for i, v in ipairs(tmp)do
        local t = {}
        local _,_, h, c, p = v:find("(.-):(.-):(.+)")
        if h and c then
          t['PathOnHost'] = h
          t['PathInContainer'] = c
          t['CgroupPermissions'] = p or nil
        else
          local _,_, h, c = v:find("(.-):(.+)")
          if h and c then
            t['PathOnHost'] = h
            t['PathInContainer'] = c
          end
        end
        if next(t) ~= nil then
          table.insert( device, t )
        end
      end
    end

    tmp = data.port or {}
    for i, v in ipairs(tmp) do
      for v1 ,v2 in string.gmatch(v, "(%d+):([^%s]+)") do
        local _,_,p= v2:find("^%d+/(%w+)")
        if p == nil then
          v2=v2..'/tcp'
        end
        portbindings[v2] = {{HostPort=v1}}
        exposedports[v2] = {HostPort=v1}
      end
    end

    local link = data.link
    tmp = data.command
    local command = {}
    if tmp ~= nil then
      for v in string.gmatch(tmp, "[^%s]+") do 
        command[#command+1] = v
      end 
    end
    if memory ~= 0 then
      _,_,n,unit = memory:find("([%d%.]+)([%l%u]+)")
      if n then
        unit = unit and unit:sub(1,1):upper() or "B"
        if  unit == "M" then
          memory = tonumber(n) * 1024 * 1024
        elseif unit == "G" then
          memory = tonumber(n) * 1024 * 1024 * 1024
        elseif unit == "K" then
          memory = tonumber(n) * 1024
        else
          memory = tonumber(n)
        end
      end
    end

    local create_body={
      Hostname = name,
      Domainname = "",
      User = user,
      Cmd = (#command ~= 0) and command or nil,
      Env = env,
      Image = image,
      Volumes = nil,
      ExposedPorts = (next(exposedports) ~= nil) and exposedports or nil,
      HostConfig = {
        Binds = (#mount ~= 0) and mount or nil,
        NetworkMode = network,
        RestartPolicy ={
          Name = restart,
          MaximumRetryCount = 0
        },
        Privileged = privileged and true or false,
        PortBindings = (next(portbindings) ~= nil) and portbindings or nil,
        Memory = memory,
        CpuShares = tonumber(cpushares),
        NanoCPUs = tonumber(cpus) * 10 ^ 9,
        BlkioWeight = tonumber(blkioweight)
      },
      NetworkingConfig = ip and {
        EndpointsConfig = {
          [network] = {
            IPAMConfig = {
              IPv4Address = ip
            }
          }
        }
      } or nil
    }
    if next(tmpfs) ~= nil then
      create_body["HostConfig"]["Tmpfs"] = tmpfs
    end
    if next(device) ~= nil then
      create_body["HostConfig"]["Devices"] = device
    end

    if network == "bridge" and next(link) ~= nil then
      create_body["HostConfig"]["Links"] = link
    end

    docker:clear_status()
    local exist_image = false
    if image then
      for _, v in ipairs (images) do
        if v.RepoTags and v.RepoTags[1] == image then
          exist_image = true
          break
        end
      end
      if not exist_image then
        local server = "index.docker.io"
        local json_stringify = luci.json and luci.json.encode or luci.jsonc.stringify
        docker:append_status("Images: " .. "pulling" .. " " .. image .. "...")
        local x_auth = nixio.bin.b64encode(json_stringify({serveraddress= server}))
        local res = dk.images:create(nil, {fromImage=image,_header={["X-Registry-Auth"]=x_auth}})
        if res and res.code < 300 then
          docker:append_status("done<br>")
        else
          docker:append_status("fail code:" .. res.code.." ".. (res.body.message and res.body.message or res.message).. "<br>")
          luci.http.redirect(luci.dispatcher.build_url("admin/docker/newcontainer"))
        end
      end
    end

    docker:append_status("Container: " .. "create" .. " " .. name .. "...")
    local res = dk.containers:create(name, nil, create_body)
    if res and res.code == 201 then
      docker:clear_status()
      luci.http.redirect(luci.dispatcher.build_url("admin/docker/containers"))
    else
      docker:append_status("fail code:" .. res.code.." ".. (res.body.message and res.body.message or res.message))
      luci.http.redirect(luci.dispatcher.build_url("admin/docker/newcontainer"))
    end
  end
end

return m