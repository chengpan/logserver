local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"
local util  = require "comm/util"
local webhdfs  = require "comm/webhdfs"
local shell = require "resty/shell"
local resty_string = require "resty/string"

local args = ngx.req.get_uri_args()
local id = tonumber(args["id"])

if not id then
	ngx.log(ngx.ERR, "no id")
	ngx.exit(ngx.HTTP_BAD_REQUEST)
end

local query_sql = "select * from tb_hadoop_files where id = "..id
ngx.log(ngx.DEBUG, "query_sql: ", query_sql)

local db, err = mysql:new()
if not db then
	ngx.log(ngx.ERR, "failed to instantiate mysql: ", err)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

db:set_timeout(1000) -- 1 sec

local ok, err, errcode, sqlstate = db:connect(conf.hadoop_db)
if not ok then
	ngx.log(ngx.ERR, "failed to connect: ", err, ": ", errcode, " ", sqlstate)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

local res, err, errcode, sqlstate = db:query(query_sql)
if not res then
	ngx.log(ngx.ERR, "bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
	ngx.log(ngx.ERR, "query_sql: ", query_sql)
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

local ok, err = db:set_keepalive(10000, 100)
if not ok then
	ngx.log(ngx.ERR, "failed to set keepalive: ", err)
	db:close()
end

if #res ~= 1 then
	ngx.log(ngx.ERR, "no corresponding info found!")
	ngx.exit(ngx.HTTP_BAD_REQUEST)	
end

local hdfs_path = res[1].hdfs_path

ngx.log(ngx.DEBUG, "file for ", id, " is ", hdfs_path)

file_size = webhdfs.get_file_size(hdfs_path)

if file_size <= 0 then
	ngx.log(ngx.ERR, hdfs_path, " not found in hadoop")
	ngx.exit(ngx.HTTP_NOT_FOUND)
end

segments = math.ceil(file_size/conf.segment_size)

local download_url_table = {}

--只提供分片下载的链接
--download_url_table[#download_url_table + 1] = conf.log_download_url.."?id="..id

for i = 0, segments - 1 do
	download_url_table[#download_url_table + 1] = conf.log_download_url.."?id="..id.."&seg="..i
end

ngx.print(json.encode(download_url_table))
ngx.exit(ngx.HTTP_OK)


