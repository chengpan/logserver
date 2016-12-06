local json  = require "cjson.safe"
local mysql = require "resty.mysql"
local conf  = require "comm/conf"
local util  = require "comm/util"
local webhdfs  = require "comm/webhdfs"
local shell = require "resty/shell"
local resty_string = require "resty/string"

local args = ngx.req.get_uri_args()
local all_domains = conf.download_whole_domains
local result_set = {err_code = 0, err_msg = "success", domains = all_domains}

local domain_name = args["domain_name"] or all_domains[1] --必须有值
local start_time = tonumber(args["start_time"])
local end_time = tonumber(args["end_time"])
local file_type = args["file_type"]

if file_type == "small" then
	file_type = 0
elseif file_type == "big" then
	file_type = 1
end

if not util.find_in_arr(domain_name, all_domains) then
	--返回只有配置的那几个域名才可以下载
	result_set.urls = json.empty_array
	ngx.print(json.encode(result_set))
	ngx.exit(ngx.HTTP_OK)
end

local query_sql = "select id, domain_name, date_hour,"
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

--最多截止到上一个小时
--Returns the current time stamp (in the format yyyy-mm-dd hh:mm:ss)
local cur_time_str = ngx.localtime()
local cur_hour_time = string.sub(cur_time_str, 1, 13)..":00:00"
query_sql = query_sql.." and date_hour < "..ngx.quote_sql_str(cur_hour_time)

--至少等待10分钟才能读取日志 10 + 60 = 70
query_sql = query_sql.." and date_hour < timestampadd(minute, -70, current_timestamp())"

--排序并限制返回结果
query_sql = query_sql.." order by date_hour desc, domain_name limit "..conf.mysql_max_results

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
	result_set.urls = json.empty_array
	ngx.print(json.encode(result_set))
	ngx.exit(ngx.HTTP_OK)
end

for i,v in ipairs(res) do
	v.file_size = webhdfs.get_file_size(v.hdfs_path)
	v.segments = math.ceil(v.file_size/conf.segment_size)
	v.download_url = conf.log_download_host..v.hdfs_path..".gz"
	v.hdfs_path = nil
end

--返回成功信息
result_set.urls = res
ngx.print(json.encode(result_set))
ngx.exit(ngx.HTTP_OK)





