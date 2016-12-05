local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"
local util  = require "comm/util"
local webhdfs  = require "comm/webhdfs"
local shell = require "resty/shell"
local resty_string = require "resty/string"

local res = ngx.location.capture("/get_log_list.lua", {args = ngx.req.get_uri_args()})

if not res then
	ngx.log(ngx.ERR, "no res")
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

if res.status ~= 200 then
	ngx.log(ngx.ERR, "res.status: ", res.status)
	ngx.exit(res.status)
end

ngx.log(ngx.DEBUG, "get_log_list: ", json.encode(res))

local log_url_array = json.decode(res.body)
if #log_url_array == 0 then
	ngx.log(ngx.DEBUG, "no logs found")
	ngx.print(json.encode(json.empty_array))
	ngx.exit(ngx.HTTP_OK)
end

local ret_urls = {}
local last_domain_name = ""
for i,v in ipairs(log_url_array) do
	local query_url = "/get_download_info.lua?id="..v.id
	ngx.log(ngx.DEBUG, "query_url: ", query_url)

	local res = ngx.location.capture(query_url)
	if not res then
		ngx.log(ngx.ERR, "no res, ", query_url)
		ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
	end

	ngx.log(ngx.DEBUG, "get_download_info.lua: ", json.encode(res))

	if res.status ~= 200 then
		ngx.log(ngx.ERR, "res.status: ", res.status, ", query_url: ", query_url)
		ngx.exit(res.status)
	end

	local download_urls = json.decode(res.body)

	if last_domain_name ~= v.domain_name then
		last_domain_name = v.domain_name
	
		v.id = nil
		v.file_type = nil
		v.file_size = nil
		v.segments = nil
		
		v.dl_urls = {}
		for ii, vv in ipairs(download_urls) do
			v.dl_urls[#v.dl_urls + 1] = vv
		end

		ret_urls[#ret_urls + 1] = v
	else
		local last_dl_urls = ret_urls[#ret_urls].dl_urls
		for ii, vv in ipairs(download_urls) do
			last_dl_urls[#last_dl_urls + 1] = vv
		end		
	end
end

ngx.print({ret_code = 0, ret_msg = "success", json.encode(ret_urls)})
ngx.exit(ngx.HTTP_OK)




