/*
 * nssml.c --
 *
 *      Standard ML language extension for AOLserver. Add the lines
 *
 *           ns_section "ns/server/mael/module/nssml"
 *           ns_param uoListFile "..../kit/basislib/basislib.ul"
 *
 *      (where .... is the exact path to the ML Kit) to your nsd.tcl 
 *      file and the line
 *
 *           ns_param nssml nssml.so
 *
 *      to the modules section.
 */

#include <stdio.h>
#include <sys/stat.h>
#include "ns.h"
#include "../Runtime/LoadKAM.h"
#include "../Runtime/Region.h"
#include "../Runtime/String.h"

#define NSSML_PATH_MAX 255
#define NSSML_ERROR_BUFF 4096

#define NSSML_OK 0
#define NSSML_FILENOTFOUND (-1)
#define NSSML_NOTIMESTAMP (-2)
#define NSSML_ULFILENOTFOUND (-3)

static char *extendedtyping = NULL;

time_t
nssml_fileModTime(char* file) 
{
  struct stat buf;
  if ( stat(file, &buf) != 0 )
    return (time_t)-1;
  return buf.st_mtime;
}    

/*
 * The Ns_ModuleVersion exported integer is used to verify
 * this module version when loaded.  For AOLserver 2.0,
 * 1 (one) is the only valid value for this variable.
 */
int Ns_ModuleVersion = 1;

static Ns_OpProc nssml_handleSmlFile;

/*
 * Temporarily, we have only one interpreter, protected with a mutex
 */

typedef struct {
  Interp* interp;
  char* hServer;
  char* hModule;
  char* prjid;
  char ulFileName[NSSML_PATH_MAX];
  char timeStampFileName[NSSML_PATH_MAX];
  time_t timeStamp;
} InterpContext;

// hack to implement filtering -  this variable
// is set during module initialization..
static InterpContext *globalInterpContext = NULL;

/*
 *----------------------------------------------------------------------
 *
 * Ns_ModuleInit --
 *
 *      This is the sml module's entry point.  AOLserver runs this
 *      function right after the module is loaded.  It is used to read
 *      configuration data, initialize data structures, and do other
 *      things at startup. In particular, global regions are
 *      initialized and the SML Basis Library is loaded together with
 *      an SML interface to access the AOLserver.
 *
 * The function is passed two parameters:
 *
 * hServer:   The server `handle' as a string. This is the
 *            short name given to the virtual server such
 *            as `server1'.
 *
 * hModule:   The module `handle' as a string. This is the
 *            short name given to the module such as `nssml'
 *
 * For example, if this module is known as `nssml' and loaded
 * into the `server1' server with entries similar to the following
 * in the nsd.ini file:
 *
 * [ns\servers]
 * server1=My First Server
 *
 * [ns\server1\modules]
 * nssml=nssml.so
 *
 * This function would be called with "server1" and "nssml" as
 * its arguments.
 *
 * Results:
 *	NS_OK or NS_ERROR
 *
 * Side effects:
 *	Module loads and initializes itself.
 *
 *---------------------------------------------------------------------- */

static int
nssml_processSmlFile(InterpContext* ctx, char* url);

Ns_Mutex stackPoolMutex;
Ns_Mutex freelistMutex;
Ns_Mutex codeCacheMutex;

void
codeCacheMutexLock()
{
  Ns_LockMutex(&codeCacheMutex);
}

void
codeCacheMutexUnlock()
{
  Ns_UnlockMutex(&codeCacheMutex);
}

void
logLoading(char *file)
{
  Ns_Log(Notice, "nssml: loaded %s", file);
}

void
logMsg(char *msg)
{
  Ns_Log(Notice, "nssml: %s", msg);
}

int
Ns_ModuleInit(char *hServer, char *hModule)
{
  InterpContext* ctx;
  char* configPath;
  char* initScript;

#ifdef REGION_PAGE_STAT
rpMap = regionPageMapNew();
#endif /* REGION_PAGE_STAT */

  // initialize stackPool Mutex, freelist Mutex, and codeCache Mutex
  Ns_InitializeMutex(&stackPoolMutex);
  Ns_InitializeMutex(&freelistMutex);
  Ns_InitializeMutex(&codeCacheMutex);

  resolveGlobalCodeFragments();

  /*
   * Create and initalize the interpreter context.
   */
  ctx = (InterpContext*)Ns_Malloc(sizeof(InterpContext));
  ctx->interp = interpNew();
  ctx->hServer = hServer;
  ctx->hModule = hModule;

  // Fetch the name of the project (prjid) from config file
  configPath = Ns_ConfigGetPath(hServer, hModule, NULL);
  ctx->prjid = Ns_ConfigGetValue(configPath, "prjid");

  if (ctx->prjid == NULL) {
    Ns_Log(Error, "nssml: You must set prjid in the config file");
    return NS_ERROR;
  }

  extendedtyping = Ns_ConfigGetValue(configPath, "extendedtyping");
  if (extendedtyping != NULL) {
    Ns_Log(Notice, "nssml: extended typing (xt) enabled");
  }


  sprintf(ctx->ulFileName, "%s/PM/%s.ul", 
	  Ns_PageRoot(hServer), ctx->prjid);
  sprintf(ctx->timeStampFileName, "%s/PM/%s.timestamp", 
	  Ns_PageRoot(hServer), ctx->prjid);
  
  ctx->timeStamp = (time_t)-1; 

  // hack to implement filtering - see below
  globalInterpContext = ctx;

  Ns_RegisterRequest(hServer, "GET", "/*.sml", 
		     nssml_handleSmlFile, NULL, ctx, 0);
  Ns_RegisterRequest(hServer, "GET", "/*.msp", 
		     nssml_handleSmlFile, NULL, ctx, 0);
  Ns_RegisterRequest(hServer, "POST", "/*.sml", 
		     nssml_handleSmlFile, NULL, ctx, 0);
  Ns_RegisterRequest(hServer, "POST", "/*.msp", 
		     nssml_handleSmlFile, NULL, ctx, 0);
    
  Ns_Log(Notice, "nssml: module is now loaded");
  Ns_Log(Notice, "nssml: ulFileName is %s", ctx->ulFileName);
  Ns_Log(Notice, "nssml: timeStampFileName is %s", ctx->timeStampFileName);

  // Execute init script if it appears in configuration file
  // Fetch init script
  initScript = Ns_ConfigGetValueExact(configPath, "initscript");    
  if ( initScript != NULL ) 
    {
      int res = nssml_processSmlFile(ctx,initScript);
      Ns_Log(Notice, "nssml: init script executed with return code %d", 
	     res);
    }
  else
    {
      Ns_Log(Notice, "nssml: No init script executed");
    }
  return NS_OK;
}

/* -------------------------------------------------
 * nssml_smlFileToUoFile - convert sml-absolute filename
 * into the uo-file for the sml-file. Also works for 
 * msp-files. Returns -1 on error.
 * ------------------------------------------------- */

int
nssml_next_sml0(char* p)
{
  if ( *(p+1) == 's' && *(p+2) == 'm' 
       && *(p+3) == 'l' && *(p+4) == '\0' )
    return 1;
  else return 0;
}

int 
nssml_smlFileToUoFile(char* hServer, char* url, char* uo, char* prjid) 
{
  char* pageRoot;
  char* p; /*  = strrchr(url, '/'); */
  int i;
  char name[NSSML_PATH_MAX];
  pageRoot = Ns_PageRoot(hServer);
  if ( strstr(url,pageRoot) != url ) {
    Ns_Log(Error, 
	   "nssml: pageRoot %s is not a substring of the requested url %s", 
	   pageRoot, url);
    return -1;
  }
  strcpy(uo, pageRoot);
  strcat(uo, "/PM/");
  strcat(uo, prjid);
  strcat(uo, "-");
  i = strlen(uo);
  p = url + strlen(pageRoot);
  if ( *p == '/' ) p++;
  while ( *p != '\0' ) {
    char c = *p;
    if ( c == '.' ) {
      if ( extendedtyping != NULL && nssml_next_sml0(p) ) {
	uo[i++] = '%';
	uo[i++] = 'g';
	uo[i++] = 'e';
	uo[i++] = 'n';
      }
      c = '%';
    } 
    if ( c == '/' ) c = '+';    
    uo[i++] = c;
    p++;
  }
  uo[i] = '\0';
  strcat(uo, ".uo");
  return 0;
}

/* ---------------------------------------------------------
 * nssml_processSmlFile - function for processing sml-files; returns
 * NSSML_OK, NSSML_NOTIMESTAMP, NSSML_FILENOTFOUND, or
 * NSSML_ULFILENOTFOUND. In case NSSML_NOTIMESTAMP or
 * NSSML_ULFILENOTFOUND is returned, the function writes a message to
 * the error log.
 * --------------------------------------------------------- */

static int
nssml_processSmlFile(InterpContext* ctx, char* url)
{
  Ns_DString ds;
  char* urlfile;                 /* the requested url as file */
  char uo[NSSML_PATH_MAX];
  int res;
  time_t t;
  char *errorStr = NULL;

  /* Check that sml-file exists */
  
  if ( Ns_UrlIsFile(ctx->hServer, url) != 1 ) {
    return NSSML_FILENOTFOUND;
  }

  /*
   * Test to see if the time stamp file exists
   */

  t = nssml_fileModTime(ctx->timeStampFileName);
  
  if ( t == (time_t)-1 )
    {
      Ns_Log(Error, 
	     "nssml: time stamp file %s not existing - web service not working",
	     &ctx->timeStampFileName);
      return NSSML_NOTIMESTAMP;
    }

  /*
   * (Re)load interpreter if timeStamps do not match
   */
 
  if ( ctx->timeStamp != t ) 
    {
      // Reload the interpreter
      FILE* is;
      char buff[NSSML_PATH_MAX];
      int count = 0;

      // free all code elements present in the
      // interpreter, including code cache entries...
      interpClear(ctx->interp);

      is = fopen(ctx->ulFileName, "r");
      if ( is == NULL ) 
	{
	  Ns_Log(Error, "nssml: Failed to open file %s for reading", 
		 &ctx->ulFileName);
	  return NSSML_ULFILENOTFOUND;
	}
    
      while ( fgets ( buff, NSSML_PATH_MAX, is ) != NULL ) 
	{
	  if ( buff[strlen(buff) - 1] == '\n' ) 
	    buff[strlen(buff) - 1] = '\0';

	  interpLoadExtend(ctx->interp, buff);
	  // Ns_Log(Notice, "nssml: Loading %s", buff);
	  count++;
	}

      // close the ul-file
      fclose(is);
      ctx->timeStamp = t;
      Ns_Log(Notice, "nssml: (Re)loaded %d uo-files", count);
    }

  Ns_DStringInit(&ds);
  Ns_UrlToFile(&ds, ctx->hServer, url);
  urlfile = ds.string;

  if ( nssml_smlFileToUoFile(ctx->hServer,urlfile,uo,ctx->prjid) == -1 ) 
    {
      return NSSML_FILENOTFOUND;
    }

  // Ns_Log(Notice, "Starting interpreter on file %s", uo);
  res = interpLoadRun(ctx->interp, uo, &errorStr);

  if ( res < 0 ) {    // uncaught exception; errorStr allocated
    if ( res == -1 )  // exception other than Interrupt raised
      {
	Ns_Log(Warning, "%s raised %s", urlfile, errorStr);
      }
    free(errorStr);   // free the malloced string 
    errorStr = NULL;  // - and nullify field    
  }
  Ns_DStringFree(&ds);

  return NSSML_OK; 
}


/* ---------------------------------------------------------
 * nssml_handleSmlFile - function for handling requests
 * for sml-files; returns an error page if the sml-file
 * does not exist.
 * --------------------------------------------------------- */

static int
nssml_handleSmlFile(Ns_OpContext context, Ns_Conn *conn)
{
  InterpContext* ctx;
  char* url;             /* the requested url */
  int res;

  ctx = (InterpContext*)context;

  res = nssml_processSmlFile(ctx, conn->request->url);

  switch ( res ) 
    {
    case NSSML_FILENOTFOUND:
      {
	Ns_ConnReturnNotFound(conn);
	return NS_ERROR;
	break;
      }
    case NSSML_ULFILENOTFOUND:
    case NSSML_NOTIMESTAMP:
      {
	Ns_ConnReturnNotice(conn, 200, 
			    "The web service is temporarily out of service",
			    "Please come back later!");
	// fall through
      }
    default:
      {
	return NS_OK;
	break;
      }	
    }
}

static int
nssml_trapProc(void *ctx, Ns_Conn *conn)
{
  char* configPath;
  char* trapScript;

  // Execute trap script if it appears in the configuration file
  configPath = Ns_ConfigGetPath(((InterpContext*)ctx)->hServer, 
				((InterpContext*)ctx)->hModule, NULL);  
  // Fetch init script
  trapScript = Ns_ConfigGetValueExact(configPath, "trapscript");    
  if ( trapScript != NULL ) 
    {
      return nssml_processSmlFile((InterpContext*)ctx, trapScript);
    }
  else
    { // We assume the path below in case there is no entry in the 
      // configuration file; for backward compatibility
      return nssml_processSmlFile((InterpContext*)ctx, "../sys/trap.sml");
    }
}

void
nssml_registerTrap(String url)
{
  char* hServer = globalInterpContext->hServer;
  Ns_RegisterRequest(hServer, "GET", &(url->data), nssml_trapProc, 
		     NULL, globalInterpContext, 0);
  Ns_RegisterRequest(hServer, "POST", &(url->data), nssml_trapProc, 
		     NULL, globalInterpContext, 0);
}

/*
 * Scheduling a script to run every N seconds
 */

static void 
nssml_scheduleScriptRun(void *url, int id)
{
  int res;
  res = nssml_processSmlFile(globalInterpContext, (char*)url);
}

void
nssml_scheduleScript(String url, int interval)       // ML function
{
  int flags = 0;
  int n;
  char *s;
  n = sizeStringDefine(url);
  s = (char*)Ns_Malloc(n+1);
  strncpy(s, &(url->data), n+1);
  Ns_ScheduleProcEx(nssml_scheduleScriptRun, s, flags, interval, NULL);
}

/*
 * Scheduling a script to run daily
 */

// ML function
void
nssml_scheduleDaily(String url, int hour, int minute)
{
  int flags = 0;
  int n;
  char *s;
  n = sizeStringDefine(url);
  s = (char*)Ns_Malloc(n+1);
  strncpy(s, &(url->data), n+1);
  Ns_ScheduleDaily(nssml_scheduleScriptRun, s, flags, 
		   hour, minute, NULL);
}


/*
 * Scheduling a script to run weekly
 */

// ML function
void
nssml_scheduleWeekly(String url, int day, int hour, int minute) 
{
  int flags = 0;
  int n;
  char *s;
  n = sizeStringDefine(url);
  s = (char*)Ns_Malloc(n+1);
  strncpy(s, &(url->data), n+1);
  Ns_ScheduleWeekly(nssml_scheduleScriptRun, s, flags, 
		    day, hour, minute, NULL);
}
