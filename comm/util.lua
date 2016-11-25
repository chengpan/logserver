local redis = require "resty.redis"
local http = require "resty.http"
local json = require "cjson.safe"

local mutex_dict = ngx.shared.mutex_dict
local domain_path_map_dict = ngx.shared.domain_path_map_dict

local _M = { _VERSION = '0.01', _AUTHOR = 'enoch' }

--返回年/月/日/时/分/秒 6个参数
_M.get_datetime = function ()
	local ltime = ngx.localtime() --yyyy-mm-dd hh:mm:ss
	local m = ngx.re.match(ltime, [[(\d+)-(\d+)-(\d+)\s+(\d+):(\d+):(\d+)]], "o")
	return m[1], m[2], m[3], m[4], m[5], m[6]
end

--2016102423 --> 2016-10-24 23:00:00
_M.mk_sql_datetime = function (datehour)
	local year = string.sub(datehour, 1, 4)
	local month = string.sub(datehour, 5, 6)
	local day = string.sub(datehour, 7, 8)
	local hour = string.sub(datehour, 9, 10)
	return string.format("%s-%s-%s %s:00:00", year, month, day, hour)
end

_M.get_mutex_lock = function (file_name)

	for i = 1, 10 do
		--expire 10s
		local ok, err, forcible = mutex_dict:add(file_name, 1, 10)
		if ok then
			ngx.log(ngx.DEBUG, "got mutex for: ", file_name, ", i :", i, ", forcible: ", forcible)
			return true
		else
			ngx.log(ngx.WARN, "get mutex failed: ", i, ", err: ", err)
			if i < 10 
			then
				ngx.sleep(1)
			end
		end
	end

	ngx.log(ngx.ERR, "can not get mutex, still locked :", file_name)
	return false
end

_M.release_mutex_lock = function (file_name)
	mutex_dict:delete(file_name)
end

--alarming system
_M.send_warning = function(title, content)
	local msg_table = {
		id = 10075,
		title = title,
		content = content
	}

	local msg_str = ngx.encode_args(msg_table)
	local httpc = http.new()
	local res, err = httpc:request_uri("http://172.23.6.144:88/monitor.cgi", {
        method = "POST",
        body = msg_str,
        headers = {
          ["Accept"] = "application/json",
          ["Content-Type"] = "application/x-www-form-urlencoded"
        }
      })

      if not res then
        ngx.log(ngx.ERR, "failed to request: ", err)
        return false
      end	

      local res_json = json.decode(res.body)
      if not res_json then
      		ngx.log(ngx.ERR, "not a json response: ", res.body)
      		return false
      end

      if res_json.errno ~= 0 then
      	    ngx.log(ngx.ERR, "errno not 0: ", res.body, "msg_str: ", msg_str)
      		return false
      end

      return true
end


_M.file_copy = function (src_path, dest_path)
    local default_unix_path = "unix:/tmp/file_copy.sock"

    local unix_path_table = {
    	"unix:/tmp/file_copy1.sock",
    	"unix:/tmp/file_copy2.sock",
    	"unix:/tmp/file_copy3.sock",
    	"unix:/tmp/file_copy4.sock",
    	"unix:/tmp/file_copy5.sock"
	}

	local rand_sock_num = math.random(#unix_path_table)

    local sock = ngx.socket.tcp()
    local ok, err = sock:connect(unix_path_table[rand_sock_num])
    if not ok then
        ngx.log(ngx.ERR, "connect to ", unix_path_table[rand_sock_num], " err: ", err)
        ok, err = sock:connect(default_unix_path)
        if not ok then
        	ngx.log(ngx.ERR, "connect to default_unix_path err: ", err)
        	return 2, err
    	end
    end

    sock:settimeout(60000)
    sock:send(src_path..","..dest_path..",")
    local  data, err, partial = sock:receive('*a')
    if not data then
        ngx.log(ngx.ERR, "receive err:", err, ", partial: ", partial)
        sock:close()
        return 2, err
    end

    ngx.log(ngx.DEBUG, "read: ", data)

    if #data < 2 then
    	ngx.log(ngx.ERR, "no data received")
        sock:close()
    	return 2, "no data"
    end

    local status = string.sub(data, 1, 1)
    status = tonumber(status)

    local msg = string.sub(data, 2, -1)

    ngx.log(ngx.DEBUG, "status: ", status, ", msg: ", msg)
    sock:close()

    return status, msg
end

_M.get_log_dir = function (domain_name)
    local log_path_table = {
        [1] = "/data1/log_server/download/",
        [2] = "/data2/log_server/download/"
    }

    local log_path = domain_path_map_dict:get(domain_name)
    if log_path then
        ngx.log(ngx.DEBUG, domain_name, "--->", log_path, " found in shared dict")
        return log_path
    end

    local crc = ngx.crc32_short(domain_name)
    local index = math.abs(crc % (#log_path_table)) + 1
    ngx.log(ngx.DEBUG, "index for ", domain_name, " is ", index)

    log_path = log_path_table[index]
    ngx.log(ngx.DEBUG, domain_name, "--->", log_path, " generated!")
 
    local ok, err, forcible = domain_path_map_dict:set(domain_name, log_path)
    if ok then
        ngx.log(ngx.DEBUG, "set domain_name<-->log_path success, forcible: ", forcible)
    else
        ngx.log(ngx.ERR, "set domain_name<-->log_path error, err: ", err)
    end

    return log_path
end

return _M