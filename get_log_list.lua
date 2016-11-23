local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"
local util  = require "comm/util"
local webhdfs  = require "comm/webhdfs"
local shell = require "resty/shell"
local resty_string = require "resty/string"

local args = ngx.req.get_uri_args()

local domain_name = args["domain_name"]
local start_time = tonumber(args["start_time"])
local end_time = tonumber(args["end_time"])
local file_type = args["file_type"]

if file_type == "small" then
	file_type = 0
elseif file_type == "big" then
	file_type = 1
end

local query_sql = "select domain_name, date_hour,"
				.." if (file_type = 0, 'small', 'big') as file_type,"
				.." hdfs_path from tb_hadoop_files where 2 > 1"

if domain_name then
	query_sql = query_sql.." and domain_name = "..ngx.quote_sql_str(domain_name)
end

if start_time and end_time then
	local condition_str = string.format(" and date_hour >= from_unixtime(%d) and date_hour <= from_unixtime(%d)",	start_time, end_time)
	query_sql = query_sql..condition_str
end

if file_type then
	query_sql = query_sql.." and file_type = "..file_type
end

--排序并限制返回结果
query_sql = query_sql.." order by date_hour desc limit "..conf.mysql_max_results

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

--空结果
if #res < 1 then
	ngx.print(json.encode(json.empty_array))
	ngx.exit(ngx.HTTP_OK)
end

for i,v in ipairs(res) do
	v.file_size = webhdfs.get_file_size(v.hdfs_path)
	v.segments = math.ceil(v.file_size/conf.segment_size)
	v.hdfs_path = nil
end

--返回成功信息
ngx.print(json.encode(res))
ngx.exit(ngx.HTTP_OK)





