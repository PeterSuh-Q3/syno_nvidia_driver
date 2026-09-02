#include <unistd.h>
#include <string.h>
#include <stdio.h>
int main(int argc,char **argv){
 if(argc!=2 || strcmp(argv[1],"postinst")!=0){fprintf(stderr,"invalid action\n");return 1;}
 if(setuid(0)!=0)return 1;
 execl("/var/packages/syno-nvidia-gpu-monitor/scripts/postinst","postinst","--root",(char*)0);
 return 1;
}
