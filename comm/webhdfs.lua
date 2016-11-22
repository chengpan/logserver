local redis = require "resty.redis"
local http = require "resty.http"
local json = require "cjson.safe"

local _M = { _VERSION = '0.01', _AUTHOR = 'enoch' }

--http://hadoop.apache.org/docs/r1.0.4/webhdfs.html#GETFILESTATUS
--curl http://10.9.101.54:50070/webhdfs/v1/logs/20161122/auc.tangdou.com/big_2016112210_access.log?op=GETFILESTATUS
_M.get_status = function (path)

	local url = "http://10.9.101.54:50070/webhdfs/v1"..path.."?op=GETFILESTATUS"
	local httpc = http.new()
	local res, err = httpc:request_uri(url)

	if not res then
		ngx.log(ngx.ERR, "failed to request: ", err)
		return false
	end	

	local res_json = json.decode(res.body)
	if not res_json then
			ngx.log(ngx.ERR, "not a json response: ", res.body)
			return false
	end

	--添加http status选项
	res_json.http_status = res.status

	return res_json 
end

return _M
