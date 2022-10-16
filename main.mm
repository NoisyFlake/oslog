#include <dlfcn.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>
#include "ActivityStreamAPI.h"

static BOOL canPrint=NO;
static int filterPid=-1;
static BOOL levelInfo=YES;
static int (*m_proc_name)(int pid,char *buffer, unsigned int size);
static os_activity_stream_for_pid_t s_os_activity_stream_for_pid;
static os_activity_stream_resume_t s_os_activity_stream_resume;
static os_activity_stream_cancel_t s_os_activity_stream_cancel;
static os_activity_stream_set_event_handler_t s_os_activity_stream_set_event_handler;
static os_log_copy_formatted_message_t s_os_log_copy_formatted_message;
static uint8_t (*m_os_log_get_type)(void *log);
static int (*m_proc_listpids)(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);


void printUsage(){
	printf("\033[1;36mUsage: \033[1;37moslog [--info|--debug] [-p <pid|name>] [--noLevelInfo]\x1b[0m\n");
}


struct ActivityInfo {
    ActivityInfo(const char *name, os_activity_id_t activity_id,
                 os_activity_id_t parent_activity_id)
        : m_name(name), m_id(activity_id), m_parent_id(parent_activity_id) {}

    const char* m_name;
    const os_activity_id_t m_id;
    const os_activity_id_t m_parent_id;
  };


bool LookupSPICalls() {
	
	static bool s_has_spi=NO;

	dlopen ("/System/Library/PrivateFrameworks/LoggingSupport.framework/LoggingSupport", RTLD_NOW);
	s_os_activity_stream_for_pid = (os_activity_stream_for_pid_t)dlsym(RTLD_DEFAULT, "os_activity_stream_for_pid");
	s_os_activity_stream_resume = (os_activity_stream_resume_t)dlsym(RTLD_DEFAULT, "os_activity_stream_resume");
	s_os_activity_stream_cancel = (os_activity_stream_cancel_t)dlsym(RTLD_DEFAULT, "os_activity_stream_cancel");
	s_os_log_copy_formatted_message = (os_log_copy_formatted_message_t)dlsym(RTLD_DEFAULT, "os_log_copy_formatted_message");
	s_os_activity_stream_set_event_handler = (os_activity_stream_set_event_handler_t)dlsym(RTLD_DEFAULT, "os_activity_stream_set_event_handler");
	m_proc_name=(int(*)(int,char *, unsigned int))dlsym(RTLD_DEFAULT, "proc_name");
	m_proc_listpids=(int(*)(uint32_t,uint32_t,void*,int))dlsym(RTLD_DEFAULT,"proc_listpids");
	m_os_log_get_type=(uint8_t(*)(void *))dlsym(RTLD_DEFAULT, "os_log_get_type");

	s_has_spi = (s_os_activity_stream_for_pid != NULL) &&
				(s_os_activity_stream_resume != NULL) &&
				(s_os_activity_stream_cancel != NULL) &&
				(s_os_log_copy_formatted_message != NULL) &&
				(s_os_activity_stream_set_event_handler != NULL) && 
				(m_os_log_get_type != NULL) &&
				(m_proc_name != NULL);

  	return s_has_spi;
  	
}



BOOL handleStreamEntry(os_activity_stream_entry_t entry, int error){
	
	if ((filterPid!=-1 && entry->pid!=filterPid) || !canPrint){
		
		return YES;
	}
	
	 if ((error == 0) && (entry != NULL) ) {
	 
		 if (entry->type==OS_ACTIVITY_STREAM_TYPE_ACTIVITY_CREATE){

    	  }
    
    
		if (entry->type==OS_ACTIVITY_STREAM_TYPE_LOG_MESSAGE) {

			os_log_message_t log_message = &entry->log_message;
			
		 
			// Get date/time
			char timebuffer[30]; 
			struct timeval tv;
			time_t curtime;
			gettimeofday(&tv, NULL); 
			curtime=tv.tv_sec;
			strftime(timebuffer,30,"%T",localtime(&curtime));
			
			// Get hostname
			char hostname[64];
			gethostname(hostname,sizeof(hostname));
			
			// Get process name
			char procname[32];
			m_proc_name(entry->pid,procname,sizeof(procname));
			
			// get log message text
			char *messageText=s_os_log_copy_formatted_message(log_message);
			
			uint8_t logLevel=m_os_log_get_type(log_message);
			const char * level=NULL;
			switch (logLevel){
				case 0x00:
					level=" <Notice>";
					break;
				case 0x01:
					level=" <Info>";
					break;
				case 0x2:
					level=" <Debug>";
					break;
				case 0x10:
					level=" <Error>";
					break;
				case 0x11:
					break;
					level=" <Fault>";
				default:
					level=" <Unknown>";
					break;
			}

			 
			if (messageText){
				printf("%s %s ""\033[1;36m""%s""\033[1;37m""[%d]%s: %s\x1b[0m\n",hostname,timebuffer,(char *)procname,entry->pid,levelInfo?level:"",messageText);
			}
		
		  }
	}      
	return YES;
}


static void NoteExitKQueueCallback(CFFileDescriptorRef f,CFOptionFlags callBackTypes, void *info)
{
    struct kevent   event;
    (void) kevent( CFFileDescriptorGetNativeDescriptor(f), NULL, 0, &event, 1, NULL);
    NSLog(@" === oslog: monitored pid [%d] terminated", (int) (pid_t) event.ident);
    exit(0);
}

int main(int argc, char **argv, char **envp) {


	if (!LookupSPICalls()){
		printf("\tError: Could not find oslog required functions. iOS >=10 is required.\n");
		return -1;
	}

	os_activity_stream_block_t block =^bool(os_activity_stream_entry_t entry, int error) {
       return handleStreamEntry(entry,error);
      };

	os_activity_stream_event_block_t stream_event_block = ^void(os_activity_stream_t stream, os_activity_stream_event_t event) {

		switch (event) {

			case OS_ACTIVITY_STREAM_EVENT_STARTED:
				char timebuffer[30];
				struct timeval tv;
				time_t curtime;
				gettimeofday(&tv, NULL); 
				curtime=tv.tv_sec;
				strftime(timebuffer,30,"%b %e %T",localtime(&curtime));
				char hostname[64];
				gethostname(hostname,sizeof(hostname));
			  	printf("%s %s: ======\n",timebuffer,hostname);
			  	canPrint=YES;
			  	break;
			case OS_ACTIVITY_STREAM_EVENT_STOPPED:
				printf("======\n");
			  	break;
			case OS_ACTIVITY_STREAM_EVENT_FAILED:
				printf("======\n");
			 	break;
			case OS_ACTIVITY_STREAM_EVENT_CHUNK_STARTED:
			 	break;
			case OS_ACTIVITY_STREAM_EVENT_CHUNK_FINISHED:
				printf("======\n");
			  	break;
			  	
		}
		
	};
	
	
	NSArray *arguments=[[NSProcessInfo processInfo] arguments];
	NSMutableArray *argumentsToUse=[arguments mutableCopy];
	[argumentsToUse removeObjectAtIndex:0];
	
	int argCount=[arguments count];
	
	if (argCount<1){
		printUsage();
		return 0;
	}
	
	uint32_t activity_stream_flags = 0;
	 
	for (NSString *arg in arguments){
		
		if ([arg isEqual:@"--info"]){
			activity_stream_flags |= OS_ACTIVITY_STREAM_INFO;
			[argumentsToUse removeObject:arg];
		}
			
		if ([arg isEqual:@"--debug"]){
			activity_stream_flags |= OS_ACTIVITY_STREAM_DEBUG;
			[argumentsToUse removeObject:arg];
		}
		
		if ([arg isEqual:@"--noLevelInfo"]){
			levelInfo=NO;
			[argumentsToUse removeObject:arg];
		}
		
			
		if ([arg isEqual:@"-p"]){
		
			int argIndex=[arguments indexOfObject:arg];
			if (argIndex==argCount-1){
				printUsage();
				return 0;
			}
			NSNumber *nspid=[arguments objectAtIndex:argIndex+1];
			int pid = [nspid intValue];
			BOOL isNameInsteadOfPid=NO;
			if (pid==0 && ![[arguments objectAtIndex:argIndex+1] isEqual:@"0"]){
				isNameInsteadOfPid=YES;
			}
			
			int bufsize = m_proc_listpids(1, 0, NULL, 0);
  			pid_t pids[2 * bufsize / sizeof(pid_t)];
			bufsize = m_proc_listpids(1, 0, pids, sizeof(pids));
			size_t num_pids = bufsize / sizeof(pid_t);
			BOOL foundPid=NO;
		 	for (int i=0; i<num_pids; i++){
		 		if (isNameInsteadOfPid){
		 			char procname[32];
					m_proc_name(pids[i],procname,sizeof(procname));
					if (strstr(procname,[[arguments objectAtIndex:argIndex+1] UTF8String])){
						pid=pids[i];
						foundPid=YES;
						break;
					}
		 		}
		 		else if (pids[i]==pid){
		 			foundPid=YES;
		 			break;
		 		}
		 	}
			if (!foundPid){
				printf("\nNo running process with id %d was found\n",pid);
				return 0;
			}
			[argumentsToUse removeObject:arg];
			[argumentsToUse removeObject:nspid];
			activity_stream_flags |= OS_ACTIVITY_STREAM_PROCESS_ONLY;
			filterPid=pid;
		}
		 
	}

	if ([argumentsToUse count]>0){
		printUsage();
		return 0;
	}
		
	os_activity_stream_t activity_stream = (*s_os_activity_stream_for_pid)(filterPid, activity_stream_flags , block);
	
	if (filterPid!=-1){
				
		int                     kq;
		struct kevent           changes;
		CFFileDescriptorContext context = { 0, NULL, NULL, NULL, NULL };
		CFRunLoopSourceRef      rls;

		kq = kqueue();

		EV_SET(&changes, filterPid, EVFILT_PROC, EV_ADD | EV_RECEIPT, NOTE_EXIT, 0, NULL);
		(void) kevent(kq, &changes, 1, &changes, 1, NULL);

		CFFileDescriptorRef noteExitKQueueRef = CFFileDescriptorCreate(NULL, kq, true, NoteExitKQueueCallback, &context);
		rls = CFFileDescriptorCreateRunLoopSource(NULL, noteExitKQueueRef, 0);
		CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
		CFRelease(rls);

		CFFileDescriptorEnableCallBacks(noteExitKQueueRef, kCFFileDescriptorReadCallBack);
	
	}	

	(*s_os_activity_stream_set_event_handler)(activity_stream, stream_event_block);

	(*s_os_activity_stream_resume)(activity_stream);
	
	[[NSRunLoop currentRunLoop] run];
	 
	 
	 (*s_os_activity_stream_cancel)(activity_stream);
    
	return 0;
}
