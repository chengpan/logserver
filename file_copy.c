/*created by enoch, 2016-11-10 11:27:33*/
#include <stdio.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <arpa/inet.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <time.h>

#define N (1024*1024)

#define LOG_PATH "/tmp/file_copy.log"

void show_time(void)
{
    time_t cur_time = time(NULL);
    printf("%s", ctime(&cur_time));
}

void file_copy(int cl)
{
    char src_path[128] = {0};
    char dest_path[128] = {0};
    char buf[N] = {0};
    int cnt = read(cl, buf, N);
    if (cnt <= 0)
    {
        perror("read");
        return;
    }

    int start_time = time(NULL);

    //printf("got: %d, %s\n", cnt, buf);

    if (buf[cnt-1] != ',')
    {
        printf("wrong format");
        return;
    }

    int i = 0, j = 0;
    while (buf[i] != ',' && buf[i] != 0)
    {
        src_path[j++] = buf[i++];
    }

    i++;
    j = 0;
    while (buf[i] != ',' && buf[i] != 0)
    {
        dest_path[j++] = buf[i++];
    }

    //printf("src_path: %s, dest_path: %s\n", src_path, dest_path);

    FILE *sfp = fopen(src_path, "r");
    if (!sfp)
    {
        perror("open src");
        return;
    }

    FILE *dfp = fopen(dest_path, "a");
    if (!dfp)
    {
        perror("open dest");
        sprintf(buf, "mkdir -p `dirname %s`", dest_path);
        printf("system command: %s\n", buf);
        system(buf);
        dfp = fopen(dest_path, "a");
        if (!dfp)
        {
            perror("still open dest failed");
            fclose(sfp);
            return;
        }
   }

    
    int total_cnt = 0;
    int rdcnt, wrcnt;
    while (1)
    {
        rdcnt = fread(buf, 1, N, sfp);
        if(rdcnt < 0)
        {
            perror("read error");
            break;
        }
		
		if (0 == rdcnt)
		{
			break;
		}

        wrcnt = fwrite(buf, 1, rdcnt, dfp);
        if (wrcnt != rdcnt)
        {
            perror("write to stream");
            break;
        }

        total_cnt += wrcnt;
    }

    fclose(sfp);
    fclose(dfp);
    if (0 == total_cnt)
    {
        printf("no bytes written for %s ==> %s\n", src_path, dest_path);
        cnt = sprintf(buf, "%d%s", 2, "no bytes written");
    }
    else
    {
        cnt = sprintf(buf, "%d%d%s", 0, total_cnt, " bytes written");
    }
    
    int end_time = time(NULL);
    
    write(cl, buf, cnt);

    int diff_time = end_time - start_time;
    if (diff_time > 20)
    {
        FILE *logfp = fopen(LOG_PATH, "a");
        if (logfp)
        {
            time_t cur_time = time(NULL);
            fprintf(logfp, "%s", ctime(&cur_time));
            fprintf(logfp, "write to %s(%d bytes) used %d seconds\n",
                dest_path, total_cnt, diff_time);
            fclose(logfp);
        }
    }
}

int main(int argc, char *argv[])
{
    if (argc != 2)
    {
        printf("%s <sock path>\n", argv[0]);
        exit(0);
    }
    const char *socket_path = argv[1];

    printf("sock path: %s, log path: %s\n", socket_path, LOG_PATH);

    unlink(socket_path);
    
    daemon(0, 0);

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path)-1);
    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
        perror("bind error");
        return errno;
    }

    if (listen(fd, 128) == -1) {
        perror("listen error");
        return errno;
    }    

    signal(SIGCHLD, SIG_IGN);
    
    int cl;
    while (1) {
        if ( (cl = accept(fd, NULL, NULL)) == -1) {
            perror("accept error");
            return errno;
        }

        if (fork()==0) {
            /* child */
            file_copy(cl);        
            close(cl);
            exit(0);
        }
        else {
            /* parent */
            close(cl);
        }
    }    

}
