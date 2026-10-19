" -*- vim -*-
" (C) 2001-2020 by William Lee, <wl1012@yahoo.com>
" }}}

if exists('g:loaded_dirdiff')
  finish
endif
let g:loaded_dirdiff = 1

" Public Interface:
command! -nargs=* -complete=dir DirDiff call <SID>DirDiff (<f-args>)
command! -nargs=0 DirDiffOpen call <SID>DirDiffOpen ()
command! -nargs=0 DirDiffNext call <SID>DirDiffNext ()
command! -nargs=0 DirDiffPrev call <SID>DirDiffPrev ()
command! -nargs=0 DirDiffUpdate call <SID>DirDiffUpdate ()
command! -nargs=0 DirDiffQuit call <SID>DirDiffQuit ()

" The following comamnds can be used in the Vim diff mode:
"
" \dg - Diff get: maps to :diffget<CR>
" \dp - Diff put: maps to :diffput<CR>
" \dj - Diff next: (think j for down)
" \dk - Diff previous: (think k for up)

if get(g:, 'DirDiffEnableMappings', 0)
    silent! exe 'nnoremap ' . get(g:, 'DirDiffGetKeyMap', '<Leader>dg') . ' :diffget<CR>'
    silent! exe 'nnoremap ' . get(g:, 'DirDiffPutKeyMap', '<Leader>dp') . ' :diffput<CR>'
    silent! exe 'nnoremap ' . get(g:, 'DirDiffNextKeyMap', '<Leader>dj') . ' :DirDiffNext<CR>'
    silent! exe 'nnoremap ' . get(g:, 'DirDiffPrevKeyMap', '<Leader>dk') . ' :DirDiffPrev<CR>'
endif

" Global Maps:

" Default Variables.  You can override these in your global variables
" settings.
"
" For DirDiffExcludes and DirDiffIgnore, separate different patterns with a
" ',' (comma and no space!).
"
" eg. in your .vimrc file: let g:DirDiffExcludes = "CVS,*.class,*.o"
"                          let g:DirDiffIgnore = "Id:"
"                          " ignore white space in diff
"                          let g:DirDiffAddArgs = "-w"
"
" You can set the pattern that diff excludes.  Defaults to the CVS directory
if !exists("g:DirDiffExcludes")
    let g:DirDiffExcludes = ""
endif
" This is the -I argument of the diff, ignore the lines of differences that
" matches the pattern
if !exists("g:DirDiffIgnore")
    let g:DirDiffIgnore = ""
endif
if !exists("g:DirDiffSort")
    let g:DirDiffSort = 1
endif
if !exists("g:DirDiffWindowSize")
    let g:DirDiffWindowSize = 14
endif
if !exists("g:DirDiffInteractive")
    let g:DirDiffInteractive = 0
endif
if !exists("g:DirDiffIgnoreCase")
    let g:DirDiffIgnoreCase = 0
endif
if !exists("g:DirDiffTheme")
    let g:DirDiffTheme = ""
endif
if !exists("g:DirDiffSimpleMap")
    let g:DirDiffSimpleMap = 0
endif
" Additional arguments
if !exists("g:DirDiffAddArgs")
    let g:DirDiffAddArgs = ""
endif
" Support for i18n (dynamically figure out the diff text)
" Defaults to off
if !exists("g:DirDiffDynamicDiffText")
    let g:DirDiffDynamicDiffText = 0
endif

if !exists("g:DirDiffIgnoreFileNameCase")
    let g:DirDiffIgnoreFileNameCase = 0
endif

" Force set the LANG variable before running the C command.  Default to C.
" Set to "" to not set the variable.
if !exists("g:DirDiffForceLang")
    let g:DirDiffForceLang = "C"
endif

" Force the shell to run the diff command to be this.  If set to  an empty
" string, the shell would not be changed.
if !exists("g:DirDiffForceShell")
    let g:DirDiffForceShell = ""
endif

" Run the diff command asynchronously via a job API instead of the
" classic blocking ":!cmd" call: NeoVim's jobstart(), or classic Vim's
" job_start().  Defaults to on when such a job API plus the buffer
" functions the streaming path needs (appendbufline()/setbufline(),
" Vim 8.2.4257+) are available; otherwise the plugin stays fully
" synchronous.  Set to 0 to force the classic synchronous path.
if !exists("g:DirDiffAsync")
    let g:DirDiffAsync = has('nvim') || (has('job') && exists('*appendbufline'))
endif
" Maximum number of concurrent diff jobs to run when fanning the
" comparison out across the top-level entries of the two directories
" (async backends only).  Clamped to the range [1, 64] when actually
" used.  A value of 1 (the default) just runs a single diff job
" asynchronously, without any fan-out.
if !exists("g:DirDiffMaxJobs")
    let g:DirDiffMaxJobs = 1
endif
" Optional per-job timeout, in milliseconds.  0 (the default) means no
" timeout is enforced.
if !exists("g:DirDiffJobTimeout")
    let g:DirDiffJobTimeout = 0
endif
" Minimum number of common entries a directory must contain, at any
" depth of the fan-out walk, before it's worth splitting further into
" one job per child instead of becoming a single atomic "diff -r" job
" for the whole subtree.  0 (the default) auto-derives a sensible value
" from g:DirDiffMaxJobs instead (see s:DirDiffFanOutThreshold()), so a
" lone big subdirectory can't become one giant serial job while every
" other entry is already done, regardless of how many jobs the user
" allows to run concurrently.
if !exists("g:DirDiffFanOutThreshold")
    let g:DirDiffFanOutThreshold = 0
endif
" Optional glob-style include pattern (or several, separated by ','
" with no space, same convention as g:DirDiffExcludes/g:DirDiffIgnore)
" restricting the comparison to only the FILE entries whose RELATIVE
" PATH -- accumulated with "/" as the separator from the root of the
" two directories being compared, regardless of platform -- matches at
" least one of the patterns.  A simple pattern with no path separator
" (eg. "*.xml") behaves exactly as if it only mattered against a base
" name: glob2regpat() leaves such a pattern unanchored at the start, so
" it still matches anywhere in the tree, same as before relative paths
" were introduced.  A pattern with a path component (eg.
" "subdir/*.xml", or "subdir\*.xml" -- backslashes are normalized to
" "/" automatically, see s:DirDiffBuildIncludeRegexes()) instead scopes
" the match to that specific subdirectory, since glob2regpat() anchors
" such a pattern at the start ("^subdir/").  Empty (the default) means
" no filtering at all -- strictly the same behaviour as before this
" variable was introduced.  Unlike g:DirDiffExcludes/g:DirDiffAddArgs,
" this is NOT passed down to the "diff" binary (GNU diff has no
" "include-only" flag, only "-x" for exclusion); it's instead applied
" by our own fan-out enumeration (see s:DirDiffCollectFanOutUnits()) so
" that a non-matching file never even gets a job queued for it.  Only
" ever consulted on the asynchronous path (including classic Vim's
" job_start()); the classic fully-synchronous path has no per-file job
" queue to filter and so does not honour this setting (see
" <SID>DirDiff()).
if !exists("g:DirDiffIncludePattern")
    let g:DirDiffIncludePattern = ""
endif

let g:DirDiffLangString = ""
if (g:DirDiffForceLang != "")
    if has('win32') && !has('win32unix')
      let g:DirDiffLangString = 'SET LANG=' . g:DirDiffForceLang . ' && '
    else
      let g:DirDiffLangString = 'LANG=' . g:DirDiffForceLang . ' '
    endif
endif

" String used for the English equivalent "Files "
if !exists("g:DirDiffTextFiles")
    let g:DirDiffTextFiles = "Files "
endif

" String used for the English equivalent " and "
if !exists("g:DirDiffTextAnd")
    let g:DirDiffTextAnd = " and "
endif

" String used for the English equivalent " differ")
if !exists("g:DirDiffTextDiffer")
    let g:DirDiffTextDiffer = " differ"
endif

" String used for the English equivalent "Only in ")
if !exists("g:DirDiffTextOnlyIn")
    let g:DirDiffTextOnlyIn = "Only in "
endif

" String used for the English equivalent ": ")
if !exists("g:DirDiffTextOnlyInCenter")
    let g:DirDiffTextOnlyInCenter = ": "
endif

" Set some script specific variables:
"
let s:DirDiffFirstDiffLine = 6
let s:DirDiffALine = 1
let s:DirDiffBLine = 2

" -- Async job state (NeoVim only).  s:DirDiffGeneration is bumped every
" time DirDiff() runs; it's captured by each job's callback at launch
" time so that a callback belonging to a superseded run (eg. the user
" pressed 'u' to update, or re-ran :DirDiff before the previous run
" finished) can recognize itself as stale and no-op instead of touching
" state/buffers that no longer apply.
let s:DirDiffGeneration = 0
" List of NeoVim job ids currently in flight, so DirDiffQuit()/Update()
" can stop them.
let s:DirDiffActiveJobs = []
" Pending work items, each a {'cmd', 'desc', 'generation'} dict.
let s:DirDiffJobQueue = []
" Accumulated stderr text per job id, keyed by job id; populated by each
" job's on_stderr callback so s:DirDiffOnJobExit() can surface diff's
" diagnostics (which otherwise never reach the user, only the exit
" code does).
let s:DirDiffJobStderr = {}
" Progress counters, also used to know when every job is done.
let s:DirDiffJobsTotal = 0
let s:DirDiffJobsDone = 0
" Number of entries the include pattern made the enumeration skip (see
" g:DirDiffIncludePattern): they matched neither by name nor as a
" structural one-sided directory.  Reported when the run ends up with
" nothing to show, so the empty result can be told apart from a genuine
" "the trees are identical" outcome.  Reset at the start of every run.
let s:DirDiffHiddenCount = 0
" Context shared by the queue pump and the job callbacks; set once per
" DirDiff() invocation, before any job is started.
let s:DirDiffJobMaxJobs = 1
let s:DirDiffJobDirA = ""
let s:DirDiffJobDirB = ""
" Argv List of "diff" arguments shared by every job of the current async
" run (see s:BuildDiffCmdArgList()); set once per DirDiff() invocation.
let s:DirDiffJobCmdArgList = []
" Buffer number of the live result buffer, built up front by
" s:DirDiffBuildSkeleton() and streamed into progressively by
" s:DirDiffStreamAppend() as job output arrives -- the one and only
" buffer used by the whole async path, whether it ends up running a
" single diff job (g:DirDiffMaxJobs <= 1, no fan-out) or several
" concurrent ones (fan-out).  g:DirDiffMaxJobs only controls
" parallelism; streaming always applies the same way regardless.  -1
" when none is active.
let s:DirDiffStatusBufNr = -1
" 1 while the live result buffer still carries its trailing progress
" line; s:DirDiffFinishStreaming() clears it once every job is done.
" s:DirDiffStreamAppend() uses it to tell whether result lines may be
" inserted above that progress line or, after finalization, must simply
" be appended at the end.  That matters because Vim can still deliver
" buffered channel data (an out_cb) after the job's exit_cb already
" triggered the "all jobs done" finalize: without the flag the insert
" would run above a progress line that no longer exists and the
" following progress refresh would overwrite the last real result line.
let s:DirDiffStreaming = 0
" Minimum time, in seconds (see reltime()/reltimefloat()), between two
" successive "visual refreshes" (window switch + :redraw) triggered by
" s:DirDiffStreamAppend().  See that function's comment for why this
" throttle exists.
let s:DirDiffRedrawThrottleSec = 0.12
" reltime() value of the last visual refresh s:DirDiffStreamAppend()
" actually performed.  An empty List is the "never refreshed yet"
" sentinel, forcing the very first call of a fresh run to always
" redraw immediately rather than waiting out the throttle above; reset
" to that sentinel by s:DirDiffBuildSkeleton() at the start of every
" run.
let s:DirDiffLastRedrawTime = []
" Classic Vim: neither of the values job_start() hands back is the plain
" positive-number job id the rest of the plugin passes around -- the Job
" object can't be compared/hashed like one, and the Channel object it
" gives the out/err callbacks isn't a Number either (E913 on ">").  So a
" job's id is its channel id (ch_info().id, 0-based) plus one, which is
" always > 0 and matches the Neovim contract; this map keeps the Job
" object so s:JobStop() can still stop it (job_stop() wants the Job, not
" a number).  Keyed the same way the callbacks can recompute it: out/err
" receive the channel, exit_cb receives the Job.  Unused under Neovim.
let s:DirDiffVimJobs = {}
" Minimal seam around the editor's async job API so the rest of the
" plugin doesn't need to sprinkle has('nvim') checks everywhere.
" Returns -1 when async execution isn't available/enabled, the same way
" callers already treat a failure to start a job.
"
" a:cmd is an argv List (never a shell string), so the job API execs it
" directly without any shell: g:DirDiffForceShell, which only ever
" affected the synchronous "!" path's shell, no longer applies to async
" jobs.  The forced LANG is passed through the job's 'env' option rather
" than a "LANG=..." shell prefix, so it no longer depends on the user's
" shell at all.
"
" The backend is picked by editor: NeoVim uses jobstart() with a
" callbacks dict; classic Vim uses job_start() with adapted callbacks
" (see the s:VimJob*Cb() adapters below) and a channel-derived id, which
" s:JobStop() and every downstream consumer already work with.
function! s:DirDiffAsyncAvailable() abort
    " appendbufline()/setbufline() (Vim 8.2.4257+) are needed by the
    " streaming path; the 'env' job option is older, so gating on these
    " covers it too.
    return has('nvim') || (has('job') && exists('*appendbufline'))
endfunction

function! s:JobStart(cmd, callbacks) abort
    if !g:DirDiffAsync || !s:DirDiffAsyncAvailable()
        return -1
    endif

    " --- NeoVim: jobstart() with a callbacks dict ---
    if has('nvim')
        " jobstart() can throw synchronously (eg. the executable doesn't
        " exist); guard it and fold that failure into the same "-1 =
        " could not start" contract the rest of the plugin already
        " handles.  The callbacks dict is copied (extend() mutates its
        " first argument) so adding 'env' never touches the caller's.
        let jobId = -1
        try
            if g:DirDiffForceLang != ""
                let jobId = jobstart(a:cmd, extend(copy(a:callbacks), {'env': {'LANG': g:DirDiffForceLang}}))
            else
                let jobId = jobstart(a:cmd, a:callbacks)
            endif
        catch
            let jobId = -1
        endtry
        return jobId
    endif

    " --- Classic Vim: job_start() with its own callback signatures ---
    let opts = {}
    if has_key(a:callbacks, 'on_stdout')
        let opts.out_cb = function('s:VimJobOutCb', [a:callbacks.on_stdout])
    endif
    if has_key(a:callbacks, 'on_stderr')
        let opts.err_cb = function('s:VimJobErrCb', [a:callbacks.on_stderr])
    endif
    if has_key(a:callbacks, 'on_exit')
        let opts.exit_cb = function('s:VimJobExitCb', [a:callbacks.on_exit])
    endif
    if g:DirDiffForceLang != ""
        let opts.env = {'LANG': g:DirDiffForceLang}
    endif
    " job_start() can throw, and can also return a job that immediately
    " reports "fail" when the command couldn't be executed; both are
    " folded into the same -1 contract.  The channel-derived id (see
    " s:DirDiffVimJobs) is what every downstream consumer (active-jobs
    " list, stderr dict, s:JobStop(), the timeout timer) expects.
    try
        let job = job_start(a:cmd, opts)
    catch
        return -1
    endtry
    if job_status(job) ==# 'fail'
        return -1
    endif
    let jobId = ch_info(job_getchannel(job)).id + 1
    let s:DirDiffVimJobs[jobId] = job
    return jobId
endfunction

" Adapters translating classic Vim's job_start() callback signatures
" into the NeoVim-shaped ones the rest of the plugin uses.
"
" Vim passes the channel as the first callback argument (NeoVim passes
" the job id), and with the default "NL" channel mode each out/err
" callback delivers exactly one message: the complete line, with its
" trailing NL stripped (and any final newline-less line is still given
" as one last message before exit).  That maps onto NeoVim's data-list
" contract as [line, '']: the trailing '' is the "empty partial
" remainder" on_stdout expects, so the line is emitted immediately.
"
" exit_cb instead gets the Job object; its channel id (recovered from
" the job) recomputes the same id s:JobStart() returned.  The job is
" dropped from s:DirDiffVimJobs here (a clean exit needs no stopping).
function! s:VimJobOutCb(on_stdout, channel, msg) abort
    call a:on_stdout(ch_info(a:channel).id + 1, [a:msg, ''], 'stdout')
endfunction

function! s:VimJobErrCb(on_stderr, channel, msg) abort
    call a:on_stderr(ch_info(a:channel).id + 1, [a:msg, ''], 'stderr')
endfunction

function! s:VimJobExitCb(on_exit, job, status) abort
    let jobId = ch_info(job_getchannel(a:job)).id + 1
    if has_key(s:DirDiffVimJobs, jobId)
        call remove(s:DirDiffVimJobs, jobId)
    endif
    call a:on_exit(jobId, a:status, 'exit')
endfunction

function! s:JobStop(id) abort
    if a:id > 0
        if has('nvim')
            silent! call jobstop(a:id)
        elseif has_key(s:DirDiffVimJobs, a:id)
            " job_stop() wants the Job object here (a bare channel number
            " is rejected with E475 on this Vim).
            silent! call job_stop(s:DirDiffVimJobs[a:id])
        endif
    endif
endfunction

" -- Variables used in various utilities
if has("unix")
    let s:DirDiffCopyCmd = "cp"
    let s:DirDiffCopyFlags = ""
    let s:DirDiffCopyDirCmd = "cp"
    let s:DirDiffCopyDirFlags = "-rf"
    let s:DirDiffCopyInteractiveFlag = "-i"

    let s:DirDiffDeleteCmd = "rm"
    let s:DirDiffDeleteFlags = ""
    let s:DirDiffDeleteInteractiveFlag = "-i"

    let s:DirDiffDeleteDirCmd = "rm"
    let s:DirDiffDeleteDirFlags = "-rf"

    let s:sep = "/"

    let s:DirDiffMakeDirCmd  = "!mkdir "

elseif has("win32")
    let s:DirDiffCopyCmd = "copy"
    let s:DirDiffCopyFlags = ""
    let s:DirDiffCopyDirCmd = "xcopy"
    let s:DirDiffCopyDirFlags = "/e /i /q"
    let s:DirDiffCopyInteractiveFlag = "/-y"

    let s:DirDiffDeleteCmd = "del"
    let s:DirDiffDeleteFlags = "/s /q"
    let s:DirDiffDeleteInteractiveFlag = "/p"
    " Windows is somewhat stupid since "del" can only remove the files, not
    " the directory.  The command "rd" would remove files recursively, but it
    " doesn't really work on a file (!).  where is the deltree command???

    let s:DirDiffDeleteDirCmd = "rd"
    " rd is by default prompting, we need to handle this in a different way
    let s:DirDiffDeleteDirFlags = "/s"
    let s:DirDiffDeleteDirQuietFlag = "/q"

    let s:sep = "\\"

    let s:DirDiffMakeDirCmd  = "!mkdir "
else
    " Platforms not supported
    let s:DirDiffCopyCmd = ""
    let s:DirDiffCopyFlags = ""
    let s:DirDiffDeleteCmd = ""
    let s:DirDiffDeleteFlags = ""
    let s:sep = ""
endif


function! <SID>DirDiff(srcA, srcB)
    " Setup
    " On Windows, Vim's <f-args>/command argument parsing collapses a
    " leading "\\" into a single "\" (eg. when the user types a UNC path
    " such as \\server\share\dir to the :DirDiff command).  This silently
    " turns a UNC path into a drive-relative path, which fnamemodify()
    " resolves by prepending the current working directory, producing a
    " bogus concatenated path and an empty diff.  Restore the doubled
    " leading backslash before resolving the path.  This is idempotent:
    " a path that already starts with "\\" is left untouched.
    let srcA = (has("win32") && a:srcA =~ '^\\[^\\]') ? '\'.a:srcA : a:srcA
    let srcB = (has("win32") && a:srcB =~ '^\\[^\\]') ? '\'.a:srcB : a:srcB
    let DirDiffAbsSrcA = fnamemodify(expand(srcA, ":p"), ":p")
    let DirDiffAbsSrcB = fnamemodify(expand(srcB, ":p"), ":p")
    " Check for an internationalized version of diff ?
    call <SID>GetDiffStrings()

    " Remove the trailing \ or /
    let DirDiffAbsSrcA = substitute(DirDiffAbsSrcA, '\\$\|/$', '', '')
    let DirDiffAbsSrcB = substitute(DirDiffAbsSrcB, '\\$\|/$', '', '')

    " A new run invalidates any async job still in flight from a previous
    " one; bump the generation counter so stale callbacks can detect
    " themselves and no-op (see s:DirDiffOnJobExit()), then actually stop
    " those previous jobs so they don't keep running to completion for
    " nothing (bad on slow/network mounts).
    let s:DirDiffGeneration = s:DirDiffGeneration + 1
    let myGeneration = s:DirDiffGeneration
    call s:DirDiffStopActiveJobs()

    let s:FilenameDiffWindow = tempname()
    " Constructs the diff command-line arguments
    let cmdarg = s:BuildDiffCmdArg()

    if (!g:DirDiffAsync || !s:DirDiffAsyncAvailable())
        " ---- Classic, fully synchronous path (identical behaviour to
        " before async support was added) ----
        let cmd = "!" . g:DirDiffLangString . "diff" . cmdarg . " \"".DirDiffAbsSrcA."\" \"".DirDiffAbsSrcB."\""
        let cmd = cmd." > \"".s:FilenameDiffWindow."\""

        echo "Diffing directories, it may take a while..."
        let error = <SID>DirDiffExec(cmd, 0)
        if (error == 0)
            redraw | echom "diff found no differences - directories match."
            return
        endif
        let resultLines = filereadable(s:FilenameDiffWindow) ? readfile(s:FilenameDiffWindow) : []
        call s:DirDiffFinalize(resultLines, DirDiffAbsSrcA, DirDiffAbsSrcB, cmdarg)
        return
    endif

    " ---- Asynchronous path (NeoVim jobstart() or Vim job_start()) ----
    let s:DirDiffJobQueue = []
    let s:DirDiffActiveJobs = []
    let s:DirDiffJobsTotal = 0
    let s:DirDiffJobsDone = 0
    let s:DirDiffHiddenCount = 0
    let s:DirDiffStreaming = 1
    let s:DirDiffJobDirA = DirDiffAbsSrcA
    let s:DirDiffJobDirB = DirDiffAbsSrcB
    let s:DirDiffJobCmdArgList = s:BuildDiffCmdArgList()
    let s:DirDiffJobMaxJobs = max([1, min([64, g:DirDiffMaxJobs])])

    " Every async run -- whether it ends up running a single diff job
    " or fans out across several -- builds the final buffer's full UI
    " shell immediately and streams result lines into it as job output
    " arrives (see s:DirDiffBuildSkeleton()/s:DirDiffStreamAppend()
    " below, and s:DirDiffPumpQueue()'s on_stdout handling).
    " g:DirDiffMaxJobs only controls how many diff processes may run
    " concurrently; it never affects how promptly results show up.
    call s:DirDiffBuildSkeleton(DirDiffAbsSrcA, DirDiffAbsSrcB, cmdarg)

    if ((s:DirDiffJobMaxJobs <= 1 && g:DirDiffIncludePattern == "") || !isdirectory(DirDiffAbsSrcA) || !isdirectory(DirDiffAbsSrcB))
        " No fan-out: a single job runs the whole comparison (still
        " "-r" recursive over the entire tree being compared), just
        " non-blocking, with its stdout streamed into the skeleton
        " line-by-line exactly like a fan-out sub-job's output would
        " be.  Also taken when either source isn't a directory: the
        " fan-out enumerator would silently produce empty listings for
        " a bad path (NeoVim's readdir() returns [] rather than
        " erroring) and flood the buffer with bogus "Only in" entries,
        " whereas the single job lets diff itself fail and report.
        " Note this branch is NOT taken when g:DirDiffIncludePattern is
        " set (and both sources are directories): a single monolithic
        " "diff -r" job has no way to leave out individual files by
        " name, so an active include pattern always routes through the
        " fan-out/collection machinery below, even when
        " g:DirDiffMaxJobs is 1 -- the resulting queue then just runs
        " one filtered job at a time instead of one unfiltered job
        " covering everything.
        let argv = ['diff'] + s:DirDiffJobCmdArgList + [DirDiffAbsSrcA, DirDiffAbsSrcB]
        call s:DirDiffQueueJob(argv, DirDiffAbsSrcA." <-> ".DirDiffAbsSrcB, myGeneration)
        let s:DirDiffJobsTotal = 1
        call s:DirDiffPumpQueue(myGeneration)
    else
        " Fan-out: partition the comparison across the top-level
        " entries of both directories so several diff jobs can run
        " concurrently; "only in" entries are shown immediately, and
        " each sub-job's own output streams in the same way as above.
        call s:DirDiffDispatchFanOut(DirDiffAbsSrcA, DirDiffAbsSrcB, myGeneration)
    endif
endfunction

" Builds the diff command-line arguments (everything except the two paths
" being compared) from the plugin's global options, as a single shell
" string.  Used by the classic synchronous path and for the "Diff Args:"
" header line; the async path builds an argv List instead via
" s:BuildDiffCmdArgList() below, which must be kept in sync with this.
function! s:BuildDiffCmdArg() abort
    let cmdarg = " -r --brief"

    if (g:DirDiffIgnoreFileNameCase)
        let cmdarg = cmdarg." --ignore-file-name-case"
    endif

    " If variable is set, we ignore the case
    if (g:DirDiffIgnoreCase)
        let cmdarg = cmdarg." -i"
    endif
    if (g:DirDiffAddArgs != "")
        let cmdarg = cmdarg." ".g:DirDiffAddArgs." "
    endif
    if (g:DirDiffExcludes != "")
        let cmdarg = cmdarg.' -x"'.substitute(g:DirDiffExcludes, ',', '" -x"', 'g').'"'
    endif
    if (g:DirDiffIgnore != "")
        let cmdarg = cmdarg.' -I"'.substitute(g:DirDiffIgnore, ',', '" -I"', 'g').'"'
    endif
    return cmdarg
endfunction

" Argv-List equivalent of s:BuildDiffCmdArg() above: same options in the
" same order, but returned as a List of individual "diff" arguments
" instead of one shell string.  Used to launch async jobs (NeoVim's
" jobstart(), or classic Vim's job_start()) without going through a
" shell, so paths and patterns containing spaces, quotes or non-ASCII
" bytes need no quoting.  Must be kept in sync with s:BuildDiffCmdArg().
function! s:BuildDiffCmdArgList() abort
    let argv = ['-r', '--brief']

    if (g:DirDiffIgnoreFileNameCase)
        call add(argv, '--ignore-file-name-case')
    endif

    " If variable is set, we ignore the case
    if (g:DirDiffIgnoreCase)
        call add(argv, '-i')
    endif
    if (g:DirDiffAddArgs != "")
        " Whitespace-split: g:DirDiffAddArgs is a convenience escape
        " hatch for extra flags, so it cannot express an argument that
        " itself contains a space (the sync path has the same
        " limitation).
        call extend(argv, split(g:DirDiffAddArgs))
    endif
    if (g:DirDiffExcludes != "")
        for pattern in split(g:DirDiffExcludes, ',')
            call extend(argv, ['-x', pattern])
        endfor
    endif
    if (g:DirDiffIgnore != "")
        for pattern in split(g:DirDiffIgnore, ',')
            call extend(argv, ['-I', pattern])
        endfor
    endif
    return argv
endfunction

" Applies every buffer-local option, keymap, syntax rule and cosmetic
" tweak (theme/simple-map) the DirDiff result buffer needs, regardless
" of whether the buffer was just built as an empty header-only skeleton
" (the async streaming path, see s:DirDiffBuildSkeleton()) or fully
" populated in one shot (the classic synchronous path, see
" s:DirDiffFinalize()).  Must be called with the diff buffer as the
" current buffer.  Idempotent; safe to call more than once.
function! s:DirDiffApplyUIChrome() abort
    setlocal filetype=dirdiff
    setlocal nomodified
    setlocal nomodifiable
    setlocal buftype=nowrite
    "setlocal buftype=nofile
    "setlocal bufhidden=delete
    setlocal bufhidden=hide
    setlocal nowrap

    " Set up local key bindings
    " 'n' actually messes with the search next pattern, I think using \dj and
    " \dk is enough.  Otherwise, use j,k, and enter.
"    nnoremap <buffer> n :call <SID>DirDiffNext()<CR>
"    nnoremap <buffer> p :call <SID>DirDiffPrev()<CR>
    nnoremap <buffer> s :. call <SID>DirDiffSync()<CR>
    vnoremap <buffer> s :call <SID>DirDiffSync()<CR>
    nnoremap <buffer> u :call <SID>DirDiffUpdate()<CR>
    nnoremap <buffer> x :call <SID>ChangeExcludes()<CR>
    nnoremap <buffer> a :call <SID>ChangeArguments()<CR>
    nnoremap <buffer> i :call <SID>ChangeIgnore()<CR>
    nnoremap <buffer> f :call <SID>ChangeIncludePattern()<CR>
    nnoremap <buffer> h :call <SID>DirDiffHexmode()<CR>
    nnoremap <buffer> w :call <SID>DirDiffWrapmode()<CR>
    nnoremap <buffer> q :call <SID>DirDiffQuit()<CR>

    nnoremap <buffer> o    :call <SID>DirDiffOpen()<CR>
    nnoremap <buffer> <CR>  :call <SID>DirDiffOpen()<CR>
    nnoremap <buffer> <2-Leftmouse> :call <SID>DirDiffOpen()<CR>
    call <SID>SetupSyntax()

    " <SID>DirDiffExec() applies these two for every synchronous "!"
    " invocation it runs; async jobs never go through it, so apply them
    " once here instead, right as the buffer becomes visible.
    if !empty(g:DirDiffTheme)
        execute "colorscheme ". g:DirDiffTheme
    endif
    if g:DirDiffSimpleMap
        nnoremap [ [c
        nnoremap ] ]c
    endif
endfunction

" Formats the trailing progress line shown at the bottom of the live
" async streaming buffer while jobs are still in flight.
function! s:DirDiffProgressText() abort
    return "Diffing... " . s:DirDiffJobsDone . "/" . s:DirDiffJobsTotal . " jobs done"
endfunction

" Applies to a single line of raw "diff --brief"-style output exactly
" the same [A]/[B] directory substitution, Windows path separator
" fixup, and 4-space indent that s:DirDiffFinalize() applies in bulk to
" the whole buffer for the classic synchronous path.  Used by the async
" streaming path to make each freshly-arrived result line presentable
" the instant it's inserted into the buffer.
function! s:DirDiffTransformLine(line, dirA, dirB) abort
    let result = a:line
    " Substitute the longer path first, same reasoning as
    " s:DirDiffFinalize(): otherwise a dir that happens to be a prefix
    " of the other one could get mismatched.
    if (strlen(a:dirA) > strlen(a:dirB))
        let result = substitute(result, <SID>EscapeDirForRegex(a:dirA), '[A]', '')
        let result = substitute(result, <SID>EscapeDirForRegex(a:dirB), '[B]', '')
    else
        let result = substitute(result, <SID>EscapeDirForRegex(a:dirB), '[B]', '')
        let result = substitute(result, <SID>EscapeDirForRegex(a:dirA), '[A]', '')
    endif
    " In windows, diff behaves somewhat weirdly, for the appened path it'll
    " use "/" instead of "\".  Convert this to \
    if (has("win32"))
        let result = substitute(result, '/', '\\', 'g')
    endif
    return '    ' . result
endfunction

" Takes the accumulated diff result lines from a single synchronous
" diff run and turns them into the final DirDiff buffer: writes them to
" the result temp file, applies the [A]/[B] substitution, the Windows
" path separator fixup, optional sorting, the header lines, the
" buffer-local options/keymaps/syntax, and finally jumps to the first
" diff entry.  Only ever called from the classic, fully-synchronous
" code path (g:DirDiffAsync disabled, or classic Vim without a usable
" job API); the async path -- whether it ends up running a single job
" or fans out across several -- always streams progressively instead,
" see s:DirDiffBuildSkeleton()/s:DirDiffFinishStreaming().
function! s:DirDiffFinalize(resultLines, dirDiffAbsSrcA, dirDiffAbsSrcB, cmdarg) abort
    call writefile(a:resultLines, s:FilenameDiffWindow)
    silent exe "edit ".s:FilenameDiffWindow
    echo "Defining [A] and [B] ... "
    " We then do a substitution on the directory path
    " We need to do substitution of the the LONGER string first, otherwise
    " it'll mix up the A and B directory
    if (strlen(a:dirDiffAbsSrcA) > strlen(a:dirDiffAbsSrcB))
	    silent! exe "%s/".<SID>EscapeDirForRegex(a:dirDiffAbsSrcA)."/[A]/"
	    silent! exe "%s/".<SID>EscapeDirForRegex(a:dirDiffAbsSrcB)."/[B]/"
    else
	    silent! exe "%s/".<SID>EscapeDirForRegex(a:dirDiffAbsSrcB)."/[B]/"
	    silent! exe "%s/".<SID>EscapeDirForRegex(a:dirDiffAbsSrcA)."/[A]/"
    endif
    " In windows, diff behaves somewhat weirdly, for the appened path it'll
    " use "/" instead of "\".  Convert this to \
    if (has("win32"))
        silent! %s/\//\\/g
    endif

    echo "Sorting entries ..."
    " We then sort the lines if the option is set
    if (g:DirDiffSort == 1)
        1,$call <SID>Sort("s:Strcmp")
    endif

    " Put in spacer in front of each line
    silent! %s/^/    /

    " We then put the file [A] and [B] on top of the diff lines
    call append(0, "[A]=". a:dirDiffAbsSrcA)
    call append(1, "[B]=". a:dirDiffAbsSrcB)
    if get(g:, 'DirDiffEnableMappings', 0)
        call append(2, "Usage:   <Enter>/'o'=open,'s'=sync,'<Leader>dg'=diffget,'<Leader>dp'=diffput,'<Leader>dj'=next,'<Leader>dk'=prev, 'q'=quit")
    else
        call append(2, "Usage:   <Enter>/'o'=open,'s'=sync,'q'=quit")
    endif
    call append(3, "Options: 'u'=update,'x'=set excludes,'i'=set ignore,'a'=set args,'f'=set file pattern, 'h'=hex mode, 'w'=wrap mode")
    call append(4, "Diff Args:" . a:cmdarg)
    call append(5, "")
    " go to the beginning of the file
    0
    call s:DirDiffApplyUIChrome()

    " Open the first diff
    call <SID>DirDiffNext()
endfunction

" Builds the final DirDiff result buffer's full UI shell (headers,
" options/keymaps, syntax, theme) immediately, before any async diff
" job -- single or fanned out -- has produced output.  Lines 1-6 (the
" [A]/[B] headers, Usage/Options/Diff Args, and the blank separator)
" match exactly what s:DirDiffFinalize() builds for the classic
" synchronous path, so every other function that hardcodes those line
" numbers (GetBaseDir, DirDiffNext, HighlightLine...) keeps working
" unmodified.  A trailing progress line is appended below the
" separator (line 7), kept up to date and eventually removed by
" s:DirDiffStreamAppend()/s:DirDiffFinishStreaming() as jobs complete.
function! s:DirDiffBuildSkeleton(dirA, dirB, cmdarg) abort
    call writefile([], s:FilenameDiffWindow)
    silent exe "edit ".s:FilenameDiffWindow
    let s:DirDiffStatusBufNr = bufnr('%')
    " Reset the redraw throttle's sentinel so the very first
    " s:DirDiffStreamAppend() call of this fresh run always redraws
    " immediately, regardless of how recently a previous (unrelated)
    " run last refreshed the screen.
    let s:DirDiffLastRedrawTime = []
    setlocal modifiable

    let headerLines = []
    call add(headerLines, "[A]=". a:dirA)
    call add(headerLines, "[B]=". a:dirB)
    if get(g:, 'DirDiffEnableMappings', 0)
        call add(headerLines, "Usage:   <Enter>/'o'=open,'s'=sync,'<Leader>dg'=diffget,'<Leader>dp'=diffput,'<Leader>dj'=next,'<Leader>dk'=prev, 'q'=quit")
    else
        call add(headerLines, "Usage:   <Enter>/'o'=open,'s'=sync,'q'=quit")
    endif
    call add(headerLines, "Options: 'u'=update,'x'=set excludes,'i'=set ignore,'a'=set args,'f'=set file pattern, 'h'=hex mode, 'w'=wrap mode")
    call add(headerLines, "Diff Args:" . a:cmdarg)
    call add(headerLines, "")

    " :edit'ing a brand-new empty file leaves exactly one empty line;
    " overwrite it with the first header line, then append the rest,
    " plus the trailing progress line, below it.
    call setline(1, headerLines[0])
    call append(1, headerLines[1:])
    call append(line('$'), s:DirDiffProgressText())

    " go to the beginning of the file
    0
    call s:DirDiffApplyUIChrome()
endfunction

" Portable buffer line count: nvim_buf_line_count() is NeoVim-only, so
" go through getbufinfo() instead (available in both editors, and the
" async gate already requires appendbufline()/setbufline()).
function! s:DirDiffBufLineCount(bufnr) abort
    return getbufinfo(a:bufnr)[0].linecount
endfunction

" Inserts newly-arrived diff result lines (already transformed via
" s:DirDiffTransformLine()) into the live async streaming buffer,
" right above the trailing progress line, and refreshes that progress
" line's text.  This is what makes entries pop into the buffer as soon
" as output arrives on a job's stdout (or as soon as a job finishes),
" rather than only once every job is done -- regardless of whether
" there's a single job running or several fanned out concurrently.
" "lines" may be empty (eg. just to refresh the progress counters); no
" insertion happens in that case.
"
" Line insertion itself operates directly on the buffer by number
" (setbufvar()/appendbufline()/setbufline()) instead of switching to
" it first: a fan-out sub-job comparing a subdirectory with many
" entries can call this function hundreds or thousands of times in
" quick succession as its stdout trickles in (eg. over a slow network
" share, where "diff --brief" produces one line every few milliseconds
" instead of all at once), and that insertion must stay cheap and
" happen every single time regardless of how often the visual refresh
" below ends up running.  See s:DirDiffRedrawThrottleSec just above
" s:DirDiffLastRedrawTime's declaration for why the refresh itself is
" rate-limited.
function! s:DirDiffStreamAppend(lines) abort
    if s:DirDiffStatusBufNr <= 0 || !bufexists(s:DirDiffStatusBufNr)
        return
    endif
    call setbufvar(s:DirDiffStatusBufNr, '&modifiable', 1)
    if s:DirDiffStreaming
        if !empty(a:lines)
            " Insert right above the trailing progress line, so new
            " entries land right after the last one already shown, in
            " arrival order -- no full re-sort/rebuild happens here, see
            " s:DirDiffFinishStreaming() for the single sort pass done
            " once every job is done.
            call appendbufline(s:DirDiffStatusBufNr, s:DirDiffBufLineCount(s:DirDiffStatusBufNr) - 1, a:lines)
        endif
        call setbufline(s:DirDiffStatusBufNr, '$', s:DirDiffProgressText())
    elseif !empty(a:lines)
        " s:DirDiffFinishStreaming() already removed the progress line:
        " this is buffered output delivered after the run was finalized,
        " so append it at the very end instead of overwriting the last
        " real result line with a progress line (see s:DirDiffStreaming).
        call appendbufline(s:DirDiffStatusBufNr, '$', a:lines)
    endif
    call setbufvar(s:DirDiffStatusBufNr, '&modifiable', 0)
    call setbufvar(s:DirDiffStatusBufNr, '&modified', 0)

    " The visual refresh (:redraw) is the expensive part -- a full
    " synchronous screen repaint -- so it's only done at most once every
    " s:DirDiffRedrawThrottleSec, no matter how often this function
    " itself gets called in between.  Without this, a fan-out sub-job
    " producing its output over a long stretch of wall-clock time (eg.
    " a subdirectory with ~1000 entries diffed over a slow UNC share)
    " could trigger hundreds of these per second; with several
    " concurrent fan-out jobs all doing the same, the cumulative cost
    " can starve that job's on_stdout processing badly enough that its
    " stdout pipe backs up (GNU diff blocking on a full pipe writing
    " its next line), making the whole run look stuck just shy of
    " completion even though every job is, in fact, still progressing.
    if !empty(s:DirDiffLastRedrawTime)
                \ && reltimefloat(reltime(s:DirDiffLastRedrawTime)) < s:DirDiffRedrawThrottleSec
        return
    endif
    let s:DirDiffLastRedrawTime = reltime()

    " Only refresh the screen when the DirDiff window is in the current
    " tab page: otherwise the user is looking somewhere else (the buffer
    " itself is already updated by number above).
    if bufwinid(s:DirDiffStatusBufNr) <= 0
        return
    endif

    " Repaint with a plain :redraw -- never switch windows: every switch
    " fires WinLeave/WinEnter, which disturbs whatever the user is doing
    " in another window of the same tab (eg. vim-visual-multi cancels its
    " selection on a window change).  :redraw repaints all windows, the
    " DirDiff one included, without moving the cursor anywhere.
    redraw
endfunction

" Message used when a run completes with no entry to display; kept in
" one function so the on-screen and background finalize paths agree.
function! s:DirDiffNoDiffMessage() abort
    let msg = "diff found no differences"
    if s:DirDiffHiddenCount > 0
        let msg = msg . " (" . s:DirDiffHiddenCount . " entries hidden by include pattern)"
    endif
    return msg
endfunction

" Finalize the result buffer when its window is not in the current tab
" page (the user switched away during a long run).  Everything is done by
" buffer number: no window is entered, no tab is switched, and the first
" diff is not auto-opened -- that only makes sense while on screen.
function! s:DirDiffFinishStreamingBackground(bufNr) abort
    " Remember the entry the user opened while streaming and strip its
    " "==> " marker before the sort below (same reason as the visible
    " path); b:currentDiff is remapped to the entry's new line after the
    " sort.
    let curDiff = getbufvar(a:bufNr, 'currentDiff', 0)
    let curText = ''
    if curDiff > s:DirDiffFirstDiffLine
        let curLine = getbufline(a:bufNr, curDiff)
        if !empty(curLine)
            let curText = substitute(curLine[0], '^==> ', '    ', '')
            if curText !=# curLine[0]
                call setbufvar(a:bufNr, '&modifiable', 1)
                call setbufline(a:bufNr, curDiff, curText)
                call setbufvar(a:bufNr, '&modifiable', 0)
                call setbufvar(a:bufNr, '&modified', 0)
            endif
        endif
    endif

    " The trailing progress line has done its job; every job is done.
    call setbufvar(a:bufNr, '&modifiable', 1)
    call deletebufline(a:bufNr, s:DirDiffBufLineCount(a:bufNr))
    call setbufvar(a:bufNr, '&modifiable', 0)
    call setbufvar(a:bufNr, '&modified', 0)

    if s:DirDiffBufLineCount(a:bufNr) <= s:DirDiffFirstDiffLine
        " Nothing was ever streamed in: same cleanup/message as the
        " visible path, without touching any window.
        silent! execute "bwipeout! " . a:bufNr
        let s:DirDiffStatusBufNr = -1
        echom s:DirDiffNoDiffMessage() . " - directories match."
        return
    endif

    if (g:DirDiffSort == 1)
        let lines = getbufline(a:bufNr, s:DirDiffFirstDiffLine + 1, '$')
        call sort(lines, 's:Strcmp')
        call setbufvar(a:bufNr, '&modifiable', 1)
        call setbufline(a:bufNr, s:DirDiffFirstDiffLine + 1, lines)
        call setbufvar(a:bufNr, '&modifiable', 0)
        call setbufvar(a:bufNr, '&modified', 0)
    endif

    " Put the "==> " marker back on the user's current entry and point
    " b:currentDiff at its new line, so DirDiffNext()/DirDiffOpen()
    " resume from there when the user comes back to this tab.
    if curText != ''
        let i = 0
        for line in getbufline(a:bufNr, s:DirDiffFirstDiffLine + 1, '$')
            if line ==# curText
                let newLine = s:DirDiffFirstDiffLine + 1 + i
                call setbufvar(a:bufNr, 'currentDiff', newLine)
                call setbufvar(a:bufNr, '&modifiable', 1)
                call setbufline(a:bufNr, newLine, substitute(line, '^    ', '==> ', ''))
                call setbufvar(a:bufNr, '&modifiable', 0)
                call setbufvar(a:bufNr, '&modified', 0)
                break
            endif
            let i += 1
        endfor
    endif
endfunction

" Called once every queued job (and the immediate "only in" entries,
" for the fan-out case) has been accounted for.  Removes the trailing
" progress line, sorts the already-displayed result lines in place (no
" full buffer rebuild -- just reordering the existing lines, same as
" the classic synchronous path does via <SID>Sort()), and cleans up the
" buffer entirely if it turns out there was nothing to show.
function! s:DirDiffFinishStreaming() abort
    if s:DirDiffStatusBufNr <= 0 || !bufexists(s:DirDiffStatusBufNr)
        return
    endif
    let bufNr = s:DirDiffStatusBufNr
    let s:DirDiffStreaming = 0

    " Only take over the screen when the user is actually sitting in the
    " DirDiff list window.  Otherwise they are working elsewhere (another
    " tab, or another window of this tab): finalize the buffer in place by
    " number -- no window switch, no :edit'ing the list into their window,
    " no auto-open of the first diff (see
    " s:DirDiffFinishStreamingBackground() above).  bufwinid() only
    " searches the current tab page, hence the -1 case too.
    if win_getid() != bufwinid(bufNr)
        call s:DirDiffFinishStreamingBackground(bufNr)
        return
    endif

    let savedWin = win_getid()
    call <SID>GotoDiffWindow()

    " Remember the entry the user is on, if they opened one while the run
    " was still streaming.  Its "==> " marker must be stripped before the
    " final sort (a bare "=" does not collate the same way as the normal
    " 4-space indent), and b:currentDiff is a line number the sort
    " invalidates, so the entry is found again afterwards.  When there is
    " one, the first diff is NOT auto-opened below: the user keeps their
    " place instead.
    let curDiff = exists('b:currentDiff') ? b:currentDiff : 0
    let curText = ''
    if curDiff > s:DirDiffFirstDiffLine
        call <SID>DeHighlightLine()
        let curText = getline(curDiff)
    endif

    setlocal modifiable
    " The trailing progress line has done its job; every job is done.
    $delete _
    setlocal nomodifiable
    setlocal nomodified

    if line('$') <= s:DirDiffFirstDiffLine
        " Nothing was ever streamed in (no "only in" entries, every
        " common entry diffed identical): behave like the synchronous
        " path and don't leave a stray, empty result buffer behind.  If
        " the include pattern hid entries, say so, so an empty result
        " isn't mistaken for "the trees are identical".
        call win_gotoid(savedWin)
        silent! execute "bwipeout! " . bufNr
        let s:DirDiffStatusBufNr = -1
        redraw | echom s:DirDiffNoDiffMessage() . " - directories match."
        return
    endif

    if (g:DirDiffSort == 1)
        setlocal modifiable
        exe (s:DirDiffFirstDiffLine + 1) . ",$call <SID>Sort(\"s:Strcmp\")"
        setlocal nomodifiable
        setlocal nomodified
    endif

    " <SID>Sort() leaves the cursor sitting on the first line of the
    " range it just sorted (line 7 here), not back at the very top of
    " the buffer; s:DirDiffFinalize() resets the cursor to the
    " beginning the same way, right before its own call to
    " <SID>DirDiffNext(), so that DirDiffNext()'s "are we still inside
    " the header?" check (line(".") < s:DirDiffFirstDiffLine) behaves
    " the same regardless of where the sort left the cursor.
    " Put the "==> " marker back on the user's current entry, now that
    " the sort is done.
    if curText != ''
        let newLine = 0
        for i in range(s:DirDiffFirstDiffLine + 1, line('$'))
            if getline(i) ==# curText
                let newLine = i
                break
            endif
        endfor
        if newLine > 0
            let b:currentDiff = newLine
            setlocal modifiable
            call setline(newLine, substitute(getline(newLine), '^    ', '==> ', ''))
            setlocal nomodifiable
            setlocal nomodified
            exe newLine
            call win_gotoid(savedWin)
            redraw
            return
        endif
    endif

    0

    call win_gotoid(savedWin)

    " No entry was open yet: open the first diff now that every entry is
    " in and sorted, same as s:DirDiffFinalize() does for the classic
    " synchronous path -- never before the sort, and only once per run.
    call <SID>DirDiffNext()
    redraw
endfunction

" Adds a unit of work (a complete "diff ..." argv List comparing two
" paths, see s:BuildDiffCmdArgList()) to the pending job queue.  "desc"
" is only used for progress/error reporting.
function! s:DirDiffQueueJob(cmd, desc, generation) abort
    call add(s:DirDiffJobQueue, {'cmd': a:cmd, 'desc': a:desc, 'generation': a:generation})
endfunction

" Starts as many queued jobs as allowed by g:DirDiffMaxJobs (clamped into
" s:DirDiffJobMaxJobs).  Safe to call repeatedly; it simply no-ops once
" the concurrency limit is reached or the queue is empty.  Also the
" single place that detects "everything is done" and triggers
" s:DirDiffMaybeFinish().
"
" Each started job's stdout streams directly into the result buffer
" line-by-line as it arrives (s:DirDiffOnJobStdout()), rather than
" being redirected to a file and read back only once the process exits:
" this is what makes a single job (g:DirDiffMaxJobs <= 1, no fan-out)
" just as progressively responsive as a fan-out batch, since "diff
" --brief" itself produces its "Only in ..."/"Files ... differ" lines
" continuously as it walks the tree, long before the process exits.
function! s:DirDiffPumpQueue(generation) abort
    if a:generation != s:DirDiffGeneration
        return
    endif
    while len(s:DirDiffActiveJobs) < s:DirDiffJobMaxJobs && !empty(s:DirDiffJobQueue)
        let work = remove(s:DirDiffJobQueue, 0)
        " One-element List holding this job's not-yet-newline-terminated
        " stdout remainder; mutated in place by s:DirDiffOnJobStdout()
        " and flushed as a final line by s:DirDiffOnJobExit() once the
        " job ends.  Vimscript Lists are passed by reference into
        " function(name, arglist)-bound closures, so both callbacks
        " below share this same mutable one-element cell despite being
        " two separate function values.
        let pending = ['']
        let OnStdout = function('s:DirDiffOnJobStdout', [a:generation, pending])
        let OnExit = function('s:DirDiffOnJobExit', [a:generation, pending, work.desc])
        let jobId = s:JobStart(work.cmd, {'on_stdout': OnStdout, 'on_stderr': function('s:DirDiffOnJobStderr'), 'on_exit': OnExit})
        if jobId > 0
            call add(s:DirDiffActiveJobs, jobId)
            if g:DirDiffJobTimeout > 0
                call timer_start(g:DirDiffJobTimeout, {-> s:JobStop(jobId)})
            endif
        else
            " Could not even start the job; treat it as an immediate
            " error so the overall run doesn't hang forever.
            let s:DirDiffJobsDone = s:DirDiffJobsDone + 1
            let errLine = s:DirDiffTransformLine("[ERROR] could not compare: " . work.desc . " (job failed to start)", s:DirDiffJobDirA, s:DirDiffJobDirB)
            call s:DirDiffStreamAppend([errLine])
        endif
    endwhile
    call s:DirDiffMaybeFinish(a:generation)
endfunction

" on_stdout callback for every diff job, whether it's the single async
" job (no fan-out) or part of a fan-out batch.  Bound via function(name,
" arglist) with (generation, pending) pre-filled; NeoVim appends
" (job_id, data, event) when invoking the callback.
"
" "data" is a List of strings that may span several on_stdout calls:
" every element except the last is guaranteed to be a complete line,
" while the last element is either a partial line still awaiting its
" trailing newline, or an empty string when the previous chunk happened
" to end exactly on a newline.  "pending" (shared with this same job's
" on_exit callback, see s:DirDiffPumpQueue()) holds the not-yet-complete
" remainder left over from the previous call: it's prefixed onto this
" call's first element, every element but the last is transformed and
" streamed into the buffer right away, and the new last element becomes
" the updated pending remainder for next time.
function! s:DirDiffOnJobStdout(generation, pending, job_id, data, event) abort
    if a:generation != s:DirDiffGeneration
        return
    endif
    if empty(a:data)
        return
    endif
    let chunk = copy(a:data)
    let chunk[0] = a:pending[0] . chunk[0]
    let a:pending[0] = remove(chunk, -1)
    if !empty(chunk)
        " Drop "Common subdirectories: ..." lines: a files-only unit
        " (no -r, see s:DirDiffCollectFanOutUnits()) emits one per
        " common subdirectory child, but those subdirs are recursed as
        " their own units, so their content is reported there and the
        " line itself is pure noise.  With -r these never appear, so
        " filtering globally is safe.  Done before the CR strip and the
        " line transform below.
        call filter(chunk, 'v:val !~# ''^Common subdirectories: ''')
        " Normalize CRLF like the classic sync path does via readfile():
        " a trailing '\r' left over from "\r\n" line endings would
        " otherwise show up as a stray '^M' in async mode only.
        let lines = map(chunk, 'substitute(v:val, ''\r$'', '''', '''')')
        let transformed = map(lines, 's:DirDiffTransformLine(v:val, s:DirDiffJobDirA, s:DirDiffJobDirB)')
        call s:DirDiffStreamAppend(transformed)
    endif
endfunction

" on_stderr callback for every diff job.  NeoVim appends (job_id, data,
" event) when invoking it, "data" being a List of strings chunked just
" like on_stdout's.  The chunks are simply joined and accumulated per
" job id in s:DirDiffJobStderr so s:DirDiffOnJobExit() can surface
" diff's diagnostics, which otherwise never reach the user (only the
" exit code does today).
function! s:DirDiffOnJobStderr(job_id, data, event) abort
    let text = join(a:data, "\n")
    if text == ''
        return
    endif
    let s:DirDiffJobStderr[a:job_id] = get(s:DirDiffJobStderr, a:job_id, '') . text
endfunction

" Common on_exit handler for every diff job, whether it's the single
" async job (no fan-out) or part of a fan-out batch.  Bound via
" function(name, arglist) with (generation, pending, desc) pre-filled,
" sharing the same "pending" remainder List as this job's on_stdout
" callback (see s:DirDiffPumpQueue()); NeoVim appends (job_id, data,
" event) when invoking the callback, where "data" is the process exit
" code.
function! s:DirDiffOnJobExit(generation, pending, desc, job_id, data, event) abort
    " Ignore callbacks from a run that's since been superseded (eg. the
    " user pressed 'u' to update, or started a brand new :DirDiff before
    " this one finished).
    if a:generation != s:DirDiffGeneration
        return
    endif

    call filter(s:DirDiffActiveJobs, 'v:val != a:job_id')

    let lines = []
    " Flush whatever's left in "pending": if the process's very last
    " write wasn't newline-terminated, on_stdout had no way to know it
    " was the last line until now -- it's still a complete, valid line.
    if !empty(a:pending[0])
        call add(lines, a:pending[0])
        let a:pending[0] = ''
    endif

    " GNU diff: 0 = identical, 1 = differences found, >=2 = a real error
    " (eg. permission denied, path not found).  Surface errors instead of
    " silently swallowing them, including a truncated snippet of whatever
    " diff wrote to stderr (see s:DirDiffOnJobStderr()).
    let stderrLines = split(substitute(get(s:DirDiffJobStderr, a:job_id, ''), '\r', '', 'g'), "\n")
    if a:data != 0 && a:data != 1
        let errLine = "[ERROR] could not compare: " . a:desc . " (code " . a:data . ")"
        if !empty(stderrLines)
            let errLine = errLine . ": " . strpart(stderrLines[0], 0, 200)
        endif
        call add(lines, errLine)
    endif
    " A clean job may never have produced stderr at all, so only drop the
    " stored text when there actually is some (remove() errors on a
    " missing key).
    if has_key(s:DirDiffJobStderr, a:job_id)
        call remove(s:DirDiffJobStderr, a:job_id)
    endif

    let s:DirDiffJobsDone = s:DirDiffJobsDone + 1

    " Show this job's trailing/flushed lines right away, already
    " formatted exactly like the buffer expects them, instead of
    " waiting for every other job to finish too.  Called even when
    " "lines" is empty, just to refresh the progress counters.
    let transformed = map(lines, 's:DirDiffTransformLine(v:val, s:DirDiffJobDirA, s:DirDiffJobDirB)')
    call s:DirDiffStreamAppend(transformed)

    call s:DirDiffPumpQueue(a:generation)
endfunction

" Called whenever a unit of work finishes (successfully or not) to check
" whether the whole async run is complete, and if so finalizes the
" already-streamed result buffer (see s:DirDiffFinishStreaming()).  The
" classic, fully-synchronous path never calls this -- it builds its
" result buffer directly via s:DirDiffFinalize() instead.
function! s:DirDiffMaybeFinish(generation) abort
    if a:generation != s:DirDiffGeneration
        return
    endif
    if s:DirDiffJobsDone < s:DirDiffJobsTotal || !empty(s:DirDiffJobQueue) || !empty(s:DirDiffActiveJobs)
        return
    endif
    call s:DirDiffFinishStreaming()
endfunction

" Safety caps bounding how far/how much s:DirDiffCollectFanOutUnits()
" (below) may recurse/probe into the directory tree while deciding how
" to partition the fan-out -- not user-facing knobs, just a guard
" against pathological trees (extremely deep nesting, or an
" unreasonably large number of directory listings) turning the
" up-front, fully-synchronous exploration pass itself into a
" noticeable stall before any job even starts.
let s:DirDiffFanOutMaxDepth = 4
let s:DirDiffFanOutProbeBudget = 500

" Returns the minimum number of common entries a directory must contain
" before s:DirDiffCollectFanOutUnits() considers it worth splitting
" further into one job per child, instead of treating the whole
" subtree as a single atomic "diff -r" job.  Honours
" g:DirDiffFanOutThreshold when the user set it explicitly (> 0);
" otherwise auto-derives a sensible value from the configured
" concurrency so there's always meaningfully more work available to
" split across jobs than there are jobs to run it, even when
" g:DirDiffMaxJobs is small.
function! s:DirDiffFanOutThreshold() abort
    if g:DirDiffFanOutThreshold > 0
        return g:DirDiffFanOutThreshold
    endif
    return max([16, 4 * s:DirDiffJobMaxJobs])
endfunction

" Returns a dict {name -> type} for one directory, where type matches
" readdirex()'s 'type' field ('dir', 'file', 'link', ...). Prefers
" readdirex() (name+type in a single round trip) when available,
" falling back to readdir()+getftype() (one extra stat per entry) on
" older Vim/NeoVim versions without it.
function! s:DirDiffListDirTyped(path) abort
    let result = {}
    if exists('*readdirex')
        for entry in readdirex(a:path)
            let result[entry.name] = entry.type
        endfor
    else
        for name in readdir(a:path)
            let result[name] = getftype(a:path . s:sep . name)
        endfor
    endif
    return result
endfunction

" Turns g:DirDiffIncludePattern into a List of Vim regex patterns ready
" for match(), one per comma-separated glob sub-pattern (eg.
" "*.xml,*.log" becomes two separate regexes), using the native
" glob2regpat() to do the glob-to-regex conversion.  Each sub-pattern
" has its backslashes normalized to forward slashes first (eg. a
" Windows-style "subdir\*.xml" typed by the user becomes
" "subdir/*.xml"), so that it matches identically regardless of which
" path separator the user typed -- the relative path it's eventually
" matched against (see s:DirDiffCollectFanOutUnits()) is itself always
" built with "/" internally, regardless of platform.  Returns an empty
" List when g:DirDiffIncludePattern is "" (the default); that empty
" List doubles as the "no filtering active at all" sentinel checked by
" every caller below via empty(), so every caller plumbing this down
" keeps working unmodified when the feature is unused.
function! s:DirDiffBuildIncludeRegexes() abort
    if g:DirDiffIncludePattern == ""
        return []
    endif
    let patterns = map(split(g:DirDiffIncludePattern, ','), 'substitute(v:val, ''\\'', ''/'', ''g'')')
    return map(patterns, 'glob2regpat(v:val)')
endfunction

" Returns truthy when "relPath" (a file's path relative to the root of
" the two directories being compared, always "/"-separated internally
" -- see s:DirDiffCollectFanOutUnits()) matches at least one of the
" regexes built by s:DirDiffBuildIncludeRegexes() (OR semantics across
" comma-separated patterns, same as the existing multiple "-x" exclude
" flags).  Only meaningful when a:includeRegexes is non-empty; callers
" are expected to check empty(a:includeRegexes) themselves first
" (meaning "no filter active, include everything") rather than call
" this function at all in that case.
function! s:DirDiffNameMatchesInclude(relPath, includeRegexes) abort
    for regex in a:includeRegexes
        if a:relPath =~# regex
            return 1
        endif
    endfor
    return 0
endfunction

" Turns g:DirDiffExcludes into a List of Vim regex patterns ready for
" match(), one per comma-separated glob sub-pattern, using glob2regpat()
" exactly like "diff" -x does.  Returns an empty List when
" g:DirDiffExcludes is "" (the default).
function! s:DirDiffBuildExcludeRegexes() abort
    if g:DirDiffExcludes == ""
        return []
    endif
    return map(split(g:DirDiffExcludes, ','), 'glob2regpat(v:val)')
endfunction

" Returns truthy when "name" (a bare base name) matches one of the
" regexes built by s:DirDiffBuildExcludeRegexes(), mirroring "diff"'s
" own "-x": matched against the base name, for files and directories
" alike, case-insensitively when g:DirDiffIgnoreFileNameCase is set
" (matching diff's --ignore-file-name-case).  Only needed on the
" include-pattern path: there each matching file becomes its own
" per-file job passing explicit operands, and "diff" does not apply
" "-x" to explicit operands -- so the exclusion has to be done here.
" The default, non-include path leaves exclusion entirely to "diff".
function! s:DirDiffIsExcluded(name, excludesRegexes) abort
    for regex in a:excludesRegexes
        if g:DirDiffIgnoreFileNameCase ? a:name =~? regex : a:name =~# regex
            return 1
        endif
    endfor
    return 0
endfunction

" Recursively walks dirA/dirB deciding how to partition the comparison
" so it can fan out across several concurrent jobs while staying
" correct and avoiding a spawn storm.
"
" Default, no include pattern (a:includeRegexes empty):
"  - the whole subtree becomes one atomic "diff -r" job when it has few
"    enough common entries (the plugin's original behaviour);
"  - otherwise it splits per SUBTREE: each common subdirectory (both
"    sides type == 'dir') recurses independently, while ALL of the
"    level's remaining common entries (files, symlinks, type
"    mismatches) are covered by a single per-level "files-only" unit
"    instead of one process per file.  That unit is a plain
"    "diff --brief <dirA> <dirB>" (no -r), so "diff" itself reports the
"    level's common-file differences, its one-sided entries (files AND
"    dirs), and a "Common subdirectories: ..." line per common subdir
"    child -- the latter dropped by s:DirDiffOnJobStdout(), since those
"    subdirs are recursed as their own units;
"  - a level with no common entries at all gets no job; its one-sided
"    entries are synthesized immediately as "Only in ..." lines.
"
" A files-only unit exists iff the level has at least one common
" non-dir child OR at least one one-sided child; when it exists, no
" one-sided line is synthesized at that level (the unit reports them).
" Falls back to treating the whole subtree as one atomic unit whenever
" the probe budget or max depth is exhausted -- this NEVER produces
" worse parallelism than the original single-level fan-out.
"
" With an include pattern active (non-empty a:includeRegexes) neither
" the atomic "diff -r" shortcut nor the files-only unit may be used:
" either would compare (and report) files that do not match, since
" "diff" is never told about the pattern.  Instead every common file
" becomes its own per-file job when its relative path matches,
" non-matching entries are silently skipped and counted in a:hidden,
" common subdirectories are always walked down to the files, and
" one-sided entries are either synthesized here (their matching files)
" or hidden (the rest, including one-sided directories).  The depth and
" probe-budget guards are NOT applied on this path: they only bound the
" up-front fan-out partitioning walk, and falling back to an atomic
" unfiltered "diff -r" job would defeat the pattern, so the whole tree
" is walked instead (directory listings only -- non-matching files
" still never get a diff job).
"
" a:units: List of units to append to; each is either [pathA, pathB]
"          (an atomic "diff -r" job) or [dirA, dirB, 'no-r'] (a
"          files-only unit covering one directory level).  The 'no-r'
"          form is never produced while an include pattern is active.
" a:onlyLines: List of raw "Only in ..." strings to append to; these
"          need no job, exactly like the original immediate-entries
"          handling.
" a:probeBudget: single-element List (mutable counter shared across the
"          whole recursive walk) decremented once per directory listing
"          actually performed, bounding total round trips globally.  Not
"          applied while an include pattern is active (see above).
" a:includeRegexes: List of regexes from s:DirDiffBuildIncludeRegexes();
"          empty means "no filtering", the default, strictly unchanged
"          behaviour.
" a:excludesRegexes: List of regexes from
"          s:DirDiffBuildExcludeRegexes(); only consulted when
"          a:includeRegexes is non-empty, to skip entries whose base
"          name matches g:DirDiffExcludes (files and directories alike,
"          and excluded directories are not recursed into).  The
"          non-include path ignores this: there "diff" itself applies
"          its own "-x" to the directories it walks.
" a:relPath: path of (a:dirA, a:dirB) relative to the root passed to
"          s:DirDiffDispatchFanOut(), accumulated one "name" component
"          at a time and always joined with "/", regardless of platform
"          -- a purely virtual construction used only to match against
"          a:includeRegexes, never a real file-system path.  "" at the
"          root.
" a:hidden: single-element List (mutable counter, like a:probeBudget)
"          accumulating the number of entries skipped because they did
"          not match the include pattern (or because a one-sided
"          directory is structural); surfaced by
"          s:DirDiffFinishStreaming() when the run ends up empty.
"
" Does not follow symlinks into directories (matches "diff -r"'s own
" default behaviour, and avoids infinite recursion on symlink cycles):
" an entry only recurses further when BOTH sides report type == 'dir'
" exactly.
function! s:DirDiffCollectFanOutUnits(dirA, dirB, depth, probeBudget, units, onlyLines, includeRegexes, excludesRegexes, relPath, hidden) abort
    " The depth/probe-budget guards bound the up-front walk that decides
    " how to partition the fan-out; when one trips, the remaining subtree
    " becomes a single atomic "diff -r" job (same results, just less
    " parallelism).  That is wrong when an include pattern is active: the
    " pattern is never passed down to "diff", so such a job would compare
    " and report non-matching files.  The include path therefore always
    " walks the whole tree (see the header comment).
    if empty(a:includeRegexes)
        if a:probeBudget[0] <= 0 || a:depth >= s:DirDiffFanOutMaxDepth
            call add(a:units, [a:dirA, a:dirB])
            return
        endif
        let a:probeBudget[0] -= 1
    endif

    let entriesA = s:DirDiffListDirTyped(a:dirA)
    let entriesB = s:DirDiffListDirTyped(a:dirB)

    let onlyA = filter(keys(entriesA), '!has_key(entriesB, v:val)')
    let onlyB = filter(keys(entriesB), '!has_key(entriesA, v:val)')
    let common = filter(keys(entriesA), 'has_key(entriesB, v:val)')

    if !empty(a:includeRegexes)
        " ---- include pattern active (see the header comment) ----
        " One-sided entries are synthesized right here, since the
        " files-only unit that would normally report them is never
        " created on this path.
        for name in onlyA
            if s:DirDiffIsExcluded(name, a:excludesRegexes)
                continue
            endif
            if get(entriesA, name, '') ==# 'dir'
                " A one-sided directory carries no file name to match
                " against; the pattern hides it.
                let a:hidden[0] += 1
            elseif s:DirDiffNameMatchesInclude(empty(a:relPath) ? name : a:relPath . '/' . name, a:includeRegexes)
                call add(a:onlyLines, s:DirDiffDiffOnlyLine . a:dirA . s:DirDiffDiffOnlyLineCenter . name)
            else
                let a:hidden[0] += 1
            endif
        endfor
        for name in onlyB
            if s:DirDiffIsExcluded(name, a:excludesRegexes)
                continue
            endif
            if get(entriesB, name, '') ==# 'dir'
                let a:hidden[0] += 1
            elseif s:DirDiffNameMatchesInclude(empty(a:relPath) ? name : a:relPath . '/' . name, a:includeRegexes)
                call add(a:onlyLines, s:DirDiffDiffOnlyLine . a:dirB . s:DirDiffDiffOnlyLineCenter . name)
            else
                let a:hidden[0] += 1
            endif
        endfor

        if empty(common)
            return
        endif

        " Common subdirectories are walked (however few entries they
        " appear to hold); every other common entry (file, symlink,
        " type mismatch) is compared by its own per-file job when its
        " relative path matches, and skipped otherwise.
        for name in common
            " An excluded entry is skipped entirely -- including a
            " common subdirectory, which is then not recursed into --
            " because these per-file operands never reach "diff"'s own
            " "-x" handling.
            if s:DirDiffIsExcluded(name, a:excludesRegexes)
                continue
            endif
            let pathA = a:dirA . s:sep . name
            let pathB = a:dirB . s:sep . name
            let childRelPath = empty(a:relPath) ? name : a:relPath . '/' . name
            if get(entriesA, name, '') ==# 'dir' && get(entriesB, name, '') ==# 'dir'
                call s:DirDiffCollectFanOutUnits(pathA, pathB, a:depth + 1, a:probeBudget, a:units, a:onlyLines, a:includeRegexes, a:excludesRegexes, childRelPath, a:hidden)
            elseif s:DirDiffNameMatchesInclude(childRelPath, a:includeRegexes)
                call add(a:units, [pathA, pathB])
            else
                let a:hidden[0] += 1
            endif
        endfor
        return
    endif

    if empty(common)
        " Nothing in common: no job will look at this directory at all
        " (neither an atomic "diff -r" job nor a files-only unit, see
        " below), so every one-sided entry at this level is synthesized
        " here, exactly as "diff --brief" would have printed it.  Any
        " level that DOES get a job reports its own one-sided entries,
        " so synthesizing them there too would duplicate them -- hence
        " this is the only place one-sided lines are ever synthesized.
        for name in onlyA
            call add(a:onlyLines, s:DirDiffDiffOnlyLine . a:dirA . s:DirDiffDiffOnlyLineCenter . name)
        endfor
        for name in onlyB
            call add(a:onlyLines, s:DirDiffDiffOnlyLine . a:dirB . s:DirDiffDiffOnlyLineCenter . name)
        endfor
        return
    endif

    if len(common) <= s:DirDiffFanOutThreshold()
        " Small enough: one atomic job for the whole subtree, no need
        " to probe any deeper (saves round trips in the common case).
        call add(a:units, [a:dirA, a:dirB])
        return
    endif

    " Large enough to be worth splitting further: recurse into every
    " common subdirectory (each one independently decides, from its
    " own listing, whether to split again); every other common entry
    " (file, symlink, type mismatch) is covered by one shared per-level
    " files-only unit, rather than one process per file -- a per-file
    " job would both spawn-storm and bypass "diff"'s own "-x" excludes,
    " which only apply when "diff" itself walks the directory.  The
    " files-only unit also reports this level's one-sided entries, so
    " they must not be synthesized here too.
    let filesOnly = (!empty(onlyA) || !empty(onlyB))
    for name in common
        let pathA = a:dirA . s:sep . name
        let pathB = a:dirB . s:sep . name
        if get(entriesA, name, '') ==# 'dir' && get(entriesB, name, '') ==# 'dir'
            call s:DirDiffCollectFanOutUnits(pathA, pathB, a:depth + 1, a:probeBudget, a:units, a:onlyLines, a:includeRegexes, a:excludesRegexes, a:relPath, a:hidden)
        else
            let filesOnly = 1
        endif
    endfor
    if filesOnly
        call add(a:units, [a:dirA, a:dirB, 'no-r'])
    endif
endfunction

" Fans the comparison out across the two directories' subtree, using
" s:DirDiffCollectFanOutUnits() to decide, adaptively, how finely to
" partition the work.  Work is split per SUBTREE, not per file: a
" common subdirectory small enough stays a single atomic "diff -r"
" job (the plugin's original, first-level-only behaviour), one large
" enough to dominate the whole run is split further so its own
" subdirectories can run as separate concurrent jobs too, and each
" split level's remaining files are handled by a single files-only
" unit (see s:DirDiffCollectFanOutUnits()) instead of one job per
" file.  This keeps a single huge common subdirectory from becoming
" one serial straggler job, without a spawn storm, and lets "diff"
" itself apply the user's excludes to each level's entries (a per-file
" job passing explicit file operands would not).  One-sided entries
" with no unit of their own are resolved immediately, without spawning
" anything, by synthesizing the same "Only in ..." line that "diff
" --brief" itself would have produced.  The whole exploration below is
" synchronous and completes before any job is queued, so the total job
" count is known up front exactly as it was before this adaptive
" partitioning was introduced.
"
" With g:DirDiffIncludePattern set, s:DirDiffCollectFanOutUnits() takes
" a different, per-file partitioning (see its own comment): only the
" matching files ever get a job queued for them, so the "total job count
" known up front" statement above still holds, just over the reduced
" set.
function! s:DirDiffDispatchFanOut(dirA, dirB, generation) abort
    let units = []
    let onlyLines = []
    let includeRegexes = s:DirDiffBuildIncludeRegexes()
    let excludesRegexes = s:DirDiffBuildExcludeRegexes()
    let hidden = [0]
    call s:DirDiffCollectFanOutUnits(a:dirA, a:dirB, 0, [s:DirDiffFanOutProbeBudget], units, onlyLines, includeRegexes, excludesRegexes, '', hidden)
    " Remember how many entries the include pattern made the walk skip,
    " for s:DirDiffFinishStreaming()'s "nothing to show" message.  Zero
    " whenever no pattern is active.
    let s:DirDiffHiddenCount = hidden[0]

    " Each unit gets its own job: atomic units ([pathA, pathB]) are
    " "diff -r" over a whole subtree, while files-only units
    " ([dirA, dirB, 'no-r']) are the same argv with the leading '-r'
    " dropped, so "diff" only looks at that one level.  The command is
    " built as an argv List (never a shell string), so paths containing
    " spaces, quotes or non-ASCII bytes need no quoting.  Units are
    " queued one job per entry rather than batched into a single
    " command: there is no cross-platform way to chain several "diff"
    " calls (and "&&" would wrongly stop a batch early anyway on GNU
    " diff's "exit code 1 = differences found").  One job per entry is
    " the simplest option that's correct on every platform; concurrency
    " is still bounded by g:DirDiffMaxJobs.
    for unit in units
        let pathA = unit[0]
        let pathB = unit[1]
        let args = s:BuildDiffCmdArgList()
        if get(unit, 2, '') ==# 'no-r'
            " '-r' is always the first element (see
            " s:BuildDiffCmdArgList()); dropping it limits this job to
            " the level's own entries (top level only).
            call remove(args, 0)
        endif
        let argv = ['diff'] + args + [pathA, pathB]
        call s:DirDiffQueueJob(argv, pathA, a:generation)
    endfor

    let s:DirDiffJobsTotal = len(s:DirDiffJobQueue)
    let s:DirDiffJobsDone = 0

    " Show the "only in" entries right away -- they don't need a job --
    " now that the progress counters reflect the real total, and
    " refresh the progress line even when there happen to be none.
    if !empty(onlyLines)
        let transformed = map(onlyLines, 's:DirDiffTransformLine(v:val, a:dirA, a:dirB)')
        call s:DirDiffStreamAppend(transformed)
    else
        call s:DirDiffStreamAppend([])
    endif

    if empty(s:DirDiffJobQueue)
        call s:DirDiffMaybeFinish(a:generation)
    else
        call s:DirDiffPumpQueue(a:generation)
    endif
endfunction

" Stops every in-flight async job and clears the pending queue.  Safe to
" call even when no job is running (eg. under classic Vim).
function! s:DirDiffStopActiveJobs() abort
    for jobId in s:DirDiffActiveJobs
        call s:JobStop(jobId)
    endfor
    let s:DirDiffActiveJobs = []
    let s:DirDiffJobQueue = []
endfunction

" Set up syntax highlighing for the diff window
"function! <SID>SetupSyntax()
function! <SID>SetupSyntax()
  if has("syntax") && exists("g:syntax_on")
      "&& !has("syntax_items")
    syn match DirDiffSrcA               "\[A\]"
    syn match DirDiffSrcB               "\[B\]"
    syn match DirDiffUsage              "^Usage.*"
    syn match DirDiffOptions            "^Options.*"
    " exec 'syn match DirDiffFiles              "' . s:DirDiffDifferLine .'"'
    " exec 'syn match DirDiffOnly               "' . s:DirDiffDiffOnlyLine . '"'
    syn match DirDiffSelected           "^==>.*" contains=DirDiffSrcA,DirDiffSrcB

    hi def link DirDiffSrcA               Directory
    hi def link DirDiffSrcB               Type
    hi def link DirDiffUsage              Special
    hi def link DirDiffOptions            Special
    hi def link DirDiffFiles              String
    hi def link DirDiffOnly               PreProc
    hi def link DirDiffSelected           DiffChange
  endif
endfunction

" You should call this within the diff window
function! <SID>DirDiffUpdate()
    call s:DirDiffStopActiveJobs()
    let dirA = <SID>GetBaseDir("A")
    let dirB = <SID>GetBaseDir("B")
    call <SID>DirDiff(dirA, dirB)
endfun

" Quit the DirDiff mode
function! <SID>DirDiffQuit()
    let in = confirm ("Are you sure you want to quit DirDiff?", "&Yes\n&No", 2)
    if (in == 1)
        call s:DirDiffStopActiveJobs()
        let s:DirDiffGeneration = s:DirDiffGeneration + 1
        call <SID>SaveDiffWindowsIfModified()
        bd!
    endif
    unlet! s:FilenameDiffWindow
    unlet! s:FilenameA
    unlet! s:FilenameB
    unlet! s:LastMode
endfun

" Returns an escaped version of the path for regex uses
function! <SID>EscapeDirForRegex(path)
    " This list is probably not complete, modify later
    return escape(a:path, "/\\[]$^~")
endfunction

" Closes a specified window
function! <SID>AskToSaveFileIfModified(file)
    let bufNum = bufnr(a:file)
    if !bufexists(bufNum)
        return
    endif

    call <SID>SaveIfModified(bufNum)
endfunction

" Close the opened diff comparison windows if they exist
function! <SID>SaveDiffWindowsIfModified()
    if exists("s:FilenameA")
        call <SID>AskToSaveFileIfModified(s:FilenameA)
    endif
    if exists("s:FilenameA")
        call <SID>AskToSaveFileIfModified(s:FilenameB)
    endif
endfunction

" Toggle hexmode from http://vim.wikia.com/wiki/Hex
function <SID>ToggleHex()
    " hex mode should be considered a read-only operation
    " save values for modified and read-only for restoration later,
    " and clear the read-only flag for now
    let l:modified=&mod
    let l:oldreadonly=&readonly
    let &readonly=0
    let l:oldmodifiable=&modifiable
    let &modifiable=1
    if !exists("b:editHex") || !b:editHex
        " save old options
        let b:oldft=&ft
        let b:oldbin=&bin
        " set new options
        setlocal binary " make sure it overrides any textwidth, etc.
        let &ft="xxd"
        " set status
        let b:editHex=1
        " switch to hex editor
        silent %!xxd
    else
        " restore old options
        let &ft=b:oldft
        if !b:oldbin
            setlocal nobinary
        endif
        " set status
        let b:editHex=0
        " return to normal editing
        silent %!xxd -r
    endif
    " restore values for modified and read only state
    let &mod=l:modified
    let &readonly=l:oldreadonly
    let &modifiable=l:oldmodifiable
endfunction

function! <SID>DirDiffHexmode()
    wincmd k
    call <SID>ToggleHex()
    wincmd l
    call <SID>ToggleHex()
    " Go back to the diff window
    wincmd j
endfunction

function! <SID>DirDiffWrapmode()
    wincmd k
    setlocal wrap!
    wincmd l
    setlocal wrap!
    " Go back to the diff window
    wincmd j
endfunction

function! <SID>EscapeFileName(path)
	if (v:version >= 702)
		return fnameescape(a:path)
	else
		" This is not a complete list of escaped character, so it's
		" not as sophisicated as the fnameescape, but this should
		" cover most of the cases and should work for Vim version <
		" 7.2
		return escape(a:path, " \t\n*?[{`$\\%#'\"|!<")
	endif
endfunction

function! <SID>EchoErr(varName, varValue)
	echoe '' . a:varName . ' : ' . a:varValue
endfunction

function! <SID>Drop(fname)
    " We need to replace the :drop implementation due to this issue:
    " https://github.com/vim/vim/issues/1503.  Thus if wideignore is set the
    " command would no work.  This is intended to work around that issue
    let winid = bufwinid(a:fname)
    if winid > 0
        call win_gotoid(winid)
    else
        exe 'edit ' a:fname
    endif
endfunction

function! <SID>GotoDiffWindow()
    call <SID>Drop(s:FilenameDiffWindow)
endfunction

" Unloading a buffer that is displayed in a window closes that window,
" so only unload the previous file when it is not the one just (re)opened
" -- which happens when DirDiffNext() reopens the same pair automatically,
" eg. right after :DirDiffUpdate rebuilt the (new) list buffer.
function! <SID>DirDiffUnloadPrevious(previous, current) abort
    if a:previous != "" && a:previous !=# a:current
        silent exec "bd ".bufnr(a:previous)
    endif
endfunction

function! <SID>DirDiffOpen()
    " Ensure we're in the right window
    call <SID>GotoDiffWindow()
    if exists("b:currentDiff") && b:currentDiff == line(".")
        return
    endif

    " First dehighlight the last marked line
    call <SID>DeHighlightLine()

    " Close existing diff windows
    call <SID>SaveDiffWindowsIfModified()

    " Change back to the right window
    call <SID>GotoDiffWindow()

    let line = getline(".")
    let b:currentDiff = line(".")

    let previousFileA = exists("s:FilenameA") ? s:FilenameA : ""
    let previousFileB = exists("s:FilenameB") ? s:FilenameB : ""

    " Parse the line and see whether it's a "Only in" or "Files Differ"
    call <SID>HighlightLine()
    let fileA = <SID>GetFileNameFromLine("A", line)
    let fileB = <SID>GetFileNameFromLine("B", line)
    let s:FilenameA = <SID>EscapeFileName(fileA)
    let s:FilenameB = <SID>EscapeFileName(fileB)

    if <SID>IsOnly(line)
        " We open the file
        let fileSrc = <SID>ParseOnlySrc(line)
        if (fileSrc == "A")
            let fileToOpen = s:FilenameA
        elseif (fileSrc == "B")
            let fileToOpen = s:FilenameB
        endif

        if exists("s:LastMode")
            if s:LastMode == 2
                silent exec "bd ".bufnr(previousFileA)

                call <SID>Drop(previousFileB)
                silent exec "edit ".fileToOpen
            else
                let previousFile = (s:LastMode == "A") ? previousFileA : previousFileB
                call <SID>Drop(previousFile)
                silent exec "edit ".fileToOpen
                call <SID>DirDiffUnloadPrevious(previousFile, fileToOpen)
            endif
        else
            silent exec "split ".fileToOpen
        endif

        " Fool the window saying that this is diff
        diffthis
        call <SID>GotoDiffWindow()
        " Resize the window
        exe("resize " . g:DirDiffWindowSize)
        exe (b:currentDiff)
        let s:LastMode = fileSrc
    elseif <SID>IsDiffer(line)

        if exists("s:LastMode")
            if s:LastMode == 2
                call <SID>Drop(previousFileA)
                silent exec "edit ".s:FilenameA
                diffthis
                call <SID>DirDiffUnloadPrevious(previousFileA, s:FilenameA)

                call <SID>Drop(previousFileB)
                silent exec "edit ".s:FilenameB
                diffthis
                call <SID>DirDiffUnloadPrevious(previousFileB, s:FilenameB)
            else
                let previousFile = (s:LastMode == "A") ? previousFileA : previousFileB
                call <SID>Drop(previousFile)
                silent exec "edit ".s:FilenameB
                call <SID>DirDiffUnloadPrevious(previousFile, s:FilenameB)
                diffthis

                " To ensure that A is on the left and B on the right, splitright must be off
                silent exec "leftabove vert diffsplit ".s:FilenameA
            endif
        else
            "Open the diff windows
            silent exec "split ".s:FilenameB

            " To ensure that A is on the left and B on the right, splitright must be off
            silent exec "leftabove vert diffsplit ".s:FilenameA
        endif

        " Go back to the diff window
        call <SID>GotoDiffWindow()
        " Resize the window
        exe("resize " . g:DirDiffWindowSize)
        exe (b:currentDiff)
        " Center the line
        exe ("normal z.")
        let s:LastMode = 2
    else
        echo "There is no diff at the current line!"
    endif
endfunction

" Ask the user to save if the buffer is modified
"
function! <SID>SaveIfModified(bufNum)
    if &autowriteall
        return
    endif

    if (getbufvar(a:bufNum, "&modified"))
        let name = bufname(a:bufNum)
        let fullName = fnamemodify(name, ":p")
        let input = confirm("File " . fullName . " has been modified.", "&Save\nCa&ncel", 1)
        if (input == 1)
            cal <SID>Drop(name)
            exec "w! ".name
        endif
    endif
endfunction

" Highlights the selected line in the diff window
"
function! <SID>HighlightLine()
    let savedLine = line(".")
    exe (b:currentDiff)
    setlocal modifiable
    let line = getline(".")
    if (match(line, "^    ") == 0)
        let line = substitute(line, "^    ", "==> ", "")
        call setline(savedLine, line)
    endif
    setlocal nomodifiable
    setlocal nomodified
    exe (savedLine)
    " This is necessary since the modified file would make the syntax
    " disappear.
    call <SID>SetupSyntax()
    redraw
endfunction

" Removes the highlight from the selected line in the diff window
"
function! <SID>DeHighlightLine()
    " Nothing to dehighlight when no entry has been opened yet on this
    " list (eg. the user pressed Enter on a freshly built list).
    if !exists("b:currentDiff")
        return
    endif
    let savedLine = line(".")
    exe (b:currentDiff)
    let line = getline(".")
    setlocal modifiable
    if (match(line, "^==> ") == 0)
        let line = substitute(line, "^==> ", "    ", "")
        call setline(line("."), line)
    endif
    setlocal nomodifiable
    setlocal nomodified
    exe (savedLine)
    redraw
endfunction

" Returns the directory for buffer "A" or "B".  You need to be in the diff
" buffer though.
function! <SID>GetBaseDir(diffName)
    let currLine = line(".")
    if (a:diffName == "A")
        let baseLine = s:DirDiffALine
    else
        let baseLine = s:DirDiffBLine
    endif
    let regex = '\['.a:diffName.'\]=\(.*\)'
    let line = getline(baseLine)
    let rtn = substitute(line, regex , '\1', '')
    return rtn
endfunction

function! <SID>DirDiffNext()
    " If the current window is a diff, go down one
    call <SID>GotoDiffWindow()
    " if the current line is <= 6, (within the header range), we go to the
    " first diff line open it
    if (line(".") < s:DirDiffFirstDiffLine)
        exe (s:DirDiffFirstDiffLine)
        let b:currentDiff = line(".")
    elseif !exists("b:currentDiff")
        " No entry has been opened yet on this list: continue from the
        " cursor line.
        let b:currentDiff = line(".")
    endif
    silent! exe (b:currentDiff + 1)
    call <SID>DirDiffOpen()
endfunction

function! <SID>DirDiffPrev()
    " If the current window is a diff, go down one
    call <SID>GotoDiffWindow()
    silent! exe (b:currentDiff - 1)
    call <SID>DirDiffOpen()
endfunction

" For each line, we can perform a recursive copy or delete to sync up the
" difference. Returns non-zero if the operation is NOT successful, returns 0
" if everything is fine.
"
function! <SID>DirDiffSyncHelper(AB, line)
    let fileA = <SID>GetFileNameFromLine("A", a:line)
    let fileB = <SID>GetFileNameFromLine("B", a:line)
"    echo "Helper line is ". a:line. " fileA " . fileA . " fileB " . fileB
    if <SID>IsOnly(a:line)
        " If a:AB is "A" and the ParseOnlySrc returns "A", that means we need to
        " copy
        let fileSrc = <SID>ParseOnlySrc(a:line)
        let operation = ""
        if (a:AB == "A" && fileSrc == "A")
            let operation = "Copy"
            " Use A, and A has source, thus copy the file from A to B
            let fileFrom = fileA
            let fileTo = fileB
        elseif (a:AB == "A" && fileSrc == "B")
            let operation = "Delete"
            " Use A, but B has source, thus delete the file from B
            let fileFrom = fileB
            let fileTo = fileA
        elseif (a:AB == "B" && fileSrc == "A")
            let operation = "Delete"
            " Use B, but the source file is A, thus removing A
            let fileFrom = fileA
            let fileTo = fileB
        elseif (a:AB == "B" && fileSrc == "B")
            " Use B, and B has the source file, thus copy B to A
            let operation = "Copy"
            let fileFrom = fileB
            let fileTo = fileA
        endif
    elseif <SID>IsDiffer(a:line)
        " Copy no matter what
        let operation = "Copy"
        if (a:AB == "A")
            let fileFrom = fileA
            let fileTo = fileB
        elseif (a:AB == "B")
            let fileFrom = fileB
            let fileTo = fileA
        endif
    else
        echo "There is no diff here!"
        " Error
        return 1
    endif
    if (operation == "Copy")
        let rtnCode = <SID>Copy(fileFrom, fileTo)
    elseif (operation == "Delete")
        let rtnCode = <SID>Delete(fileFrom)
    endif
    return rtnCode
endfunction

" Synchronize the range
function! <SID>DirDiffSync() range
    let answer = 1
    let silence = 0
    let syncMaster = "A"
    let currLine = a:firstline
    let lastLine = a:lastline
    let syncCount = 0

    while ((currLine <= lastLine))
        " Update the highlight
        call <SID>DeHighlightLine()
        let b:currentDiff = currLine
        call <SID>HighlightLine()
        let line = getline(currLine)
        if (!silence)
            let answer = confirm(substitute(line, "^....", '', ''). "\nSynchronization option:" , "&A -> B\n&B -> A\nA&lways A\nAl&ways B\n&Skip\nCa&ncel", 6)
            if (answer == 1 || answer == 3)
                let syncMaster = "A"
            endif
            if (answer == 2 || answer == 4)
                let syncMaster = "B"
            endif
            if (answer == 3 || answer == 4)
                let silence = 1
            endif
            if (answer == 5)
                let currLine = currLine + 1
                continue
            endif
            if (answer == 6)
                break
            endif
        endif

"        call <SID>DeHighlightLine()
        let rtnCode = <SID>DirDiffSyncHelper(syncMaster, line)
        if (rtnCode == 0)
            " Successful
            let syncCount = syncCount + 1
            " Assume that the line is synchronized, we delete the entry
            setlocal modifiable
            exe (currLine.",".currLine." delete")
            setlocal nomodifiable
            setlocal nomodified
            let lastLine = lastLine - 1
        else
            " Failed!
            let currLine = currLine + 1
        endif
    endwhile
    redraw!
    echo syncCount . " diff item(s) synchronized."
endfunction

" Return file "A" or "B" depending on the line given.  If it's a Only line,
" either A or B does not exist, but the according value would be returned.
function! <SID>GetFileNameFromLine(AB, line)
    " Determine where the source of the copy is.
    let dirA = <SID>GetBaseDir("A")
    let dirB = <SID>GetBaseDir("B")

    let fileToProcess = ""

    if <SID>IsOnly(a:line)
        let fileToProcess = <SID>ParseOnlyFile(a:line)
    elseif <SID>IsDiffer(a:line)
        let regex = '^.*' . s:DirDiffDifferLine . '\[A\]\(.*\)' . s:DirDiffDifferAndLine . '\[B\]\(.*\)' . s:DirDiffDifferEndLine . '.*$'
        let fileToProcess = substitute(a:line, regex, '\1', '')
    else
    endif

    "echo "line : " . a:line. "AB = " . a:AB . " File to Process " . fileToProcess
    if (a:AB == "A")
        return dirA . fileToProcess
    elseif (a:AB == "B")
        return dirB . fileToProcess
    else
        return ""
    endif
endfunction

"Returns the source (A or B) of the "Only" line
function! <SID>ParseOnlySrc(line)
    return substitute(a:line, '^.*' . s:DirDiffDiffOnlyLine . '\[\(.\)\].*' . s:DirDiffDiffOnlyLineCenter . '.*', '\1', '')
endfunction

function! <SID>ParseOnlyFile(line)
    let regex = '^.*' . s:DirDiffDiffOnlyLine . '\[.\]\(.*\)' . s:DirDiffDiffOnlyLineCenter . '\(.*\)'
    let root = substitute(a:line, regex , '\1', '')
    let file = root . s:sep . substitute(a:line, regex , '\2', '')
    return file
endfunction

function! <SID>Copy(fileFromOrig, fileToOrig)
    let fileFrom = substitute(a:fileFromOrig, '/', s:sep, 'g')
    let fileTo = substitute(a:fileToOrig, '/', s:sep, 'g')
    echo "Copy from " . fileFrom . " to " . fileTo
    if (s:DirDiffCopyCmd == "")
        echo "Copy not supported on this platform"
        return 1
    endif

    " Constructs the copy command
    let copycmd = "!".s:DirDiffCopyCmd." ".s:DirDiffCopyFlags
    " Append the interactive flag
    if (g:DirDiffInteractive)
        let copycmd = copycmd . " " . s:DirDiffCopyInteractiveFlag
    endif
    let copycmd = copycmd . " \"".fileFrom."\" \"".fileTo."\""

    " Constructs the copy directory command
    let copydircmd = "!".s:DirDiffCopyDirCmd." ".s:DirDiffCopyDirFlags
    " Append the interactive flag
    if (g:DirDiffInteractive)
        let copydircmd = copydircmd . " " . s:DirDiffCopyInteractiveFlag
    endif
    let copydircmd = copydircmd . " \"".fileFrom."\" \"".fileTo."\""

    let error = 0
    if (isdirectory(fileFrom))
        let error = <SID>DirDiffExec(copydircmd, g:DirDiffInteractive)
    else
        let error = <SID>DirDiffExec(copycmd, g:DirDiffInteractive)
    endif
    if (error != 0)
        echo "Can't copy from " . fileFrom . " to " . fileTo
        return 1
    endif
    return 0
endfunction

" Would execute the command, either silent or not silent, by the
" interactive flag ([0|1]).  Returns the v:shell_error after
" executing the command.
function! <SID>DirDiffExec(cmd, interactive)
    let error = 0
    " On Unix, if we use a different shell other than bash, we can cause
    " problem
    if g:DirDiffForceShell != ""
        let shell_save = &shell
        let &shell = g:DirDiffForceShell
    endif
    if (a:interactive)
        exe (a:cmd)
        let error = v:shell_error
    else
        silent exe (a:cmd)
        let error = v:shell_error
    endif
    if g:DirDiffForceShell != ""
        let &shell = shell_save
    endif
"    let d = input("DirDiffExec: " . a:cmd . " " . a:interactive . " returns " . v:shell_error)
    if !empty(g:DirDiffTheme)
      execute "colorscheme ". g:DirDiffTheme
    endif
    if g:DirDiffSimpleMap
    	nnoremap [ [c
	    nnoremap ] ]c
    endif
    return error
endfunction

" Delete the file or directory.  Returns 0 if nothing goes wrong, error code
" otherwise.
function! <SID>Delete(fileFromOrig)
    let fileFrom = substitute(a:fileFromOrig, '/', s:sep, 'g')
    echo "Deleting from " . fileFrom
    if (s:DirDiffDeleteCmd == "")
        echo "Delete not supported on this platform"
        return 1
    endif

    let delcmd = ""

    if (isdirectory(fileFrom))
        let delcmd = "!".s:DirDiffDeleteDirCmd." ".s:DirDiffDeleteDirFlags
        if (g:DirDiffInteractive)
            " If running on Unix, and we're running in interactive mode, we
            " append the -i tag
            if (has("unix"))
                let delcmd = delcmd . " " . s:DirDiffDeleteInteractiveFlag
            endif
        else
            " If running on windows, and we're not running in interactive
            " mode, we append the quite flag to the "rd" command
            if (has("win32"))
                let delcmd = delcmd . " " . s:DirDiffDeleteDirQuietFlag
            endif
        endif
    else
        let delcmd = "!".s:DirDiffDeleteCmd." ".s:DirDiffDeleteFlags
        if (g:DirDiffInteractive)
            let delcmd = delcmd . " " . s:DirDiffDeleteInteractiveFlag
        endif
    endif

    let delcmd = delcmd ." \"".fileFrom."\""
    let error = <SID>DirDiffExec(delcmd, g:DirDiffInteractive)
    if (error != 0)
        echo "Can't delete " . fileFrom
    endif
    return error
endfunction

" The given line begins with the "Only in"
function! <SID>IsOnly(line)
    return (match(a:line, "^ *" . s:DirDiffDiffOnlyLine . "\\|^==> " . s:DirDiffDiffOnlyLine ) == 0)
endfunction

" The given line begins with the "Files"
function! <SID>IsDiffer(line)
    return (match(a:line, "^ *" . s:DirDiffDifferLine . "\\|^==> " . s:DirDiffDifferLine  ) == 0)
endfunction

" Let you modify the Exclude patthern
function! <SID>ChangeExcludes()
    let g:DirDiffExcludes = input ("Exclude pattern (separate multiple patterns with ','): ", g:DirDiffExcludes)
    echo "\nPress update ('u') to refresh the diff."
endfunction

" Let you modify additional arguments for diff
function! <SID>ChangeArguments()
    let g:DirDiffAddArgs = input ("Additional diff args: ", g:DirDiffAddArgs)
    echo "\nPress update ('u') to refresh the diff."
endfunction

" Let you modify the Ignore patthern
function! <SID>ChangeIgnore()
    let g:DirDiffIgnore = input ("Ignore pattern (separate multiple patterns with ','): ", g:DirDiffIgnore)
    echo "\nPress update ('u') to refresh the diff."
endfunction

" Let you modify the file include pattern (asynchronous path only --
" see g:DirDiffIncludePattern's own definition above).  The pattern may
" include a path prefix to scope it to a specific subdirectory (eg.
" "subdir/*.xml" or "subdir\*.xml", both equivalent); a plain pattern
" with no path separator still matches anywhere in the tree as before.
function! <SID>ChangeIncludePattern()
    let g:DirDiffIncludePattern = input ("File include pattern, optionally with a path prefix like 'subdir/*.xml' (separate multiple patterns with ','): ", g:DirDiffIncludePattern)
    if g:DirDiffAsync == 0
        echom "Note: g:DirDiffIncludePattern is only honored on the asynchronous path (g:DirDiffAsync is 0)."
    endif
    echo "\nPress update ('u') to refresh the diff."
endfunction

" Sorting functions from the Vim docs.  Use this instead of the sort binary.
"
" Function for use with Sort(), to compare two strings.
func! <SID>Strcmp(str1, str2)
  if (a:str1 < a:str2)
	return -1
  elseif (a:str1 > a:str2)
	return 1
  else
	return 0
  endif
endfunction

" Sort lines.  SortR() is called recursively.
func! <SID>SortR(start, end, cmp)
  if (a:start >= a:end)
	return
  endif
  let partition = a:start - 1
  let middle = partition
  let partStr = getline((a:start + a:end) / 2)
  let i = a:start
  while (i <= a:end)
	let str = getline(i)
	exec "let result = " . a:cmp . "(str, partStr)"
	if (result <= 0)
	    " Need to put it before the partition.  Swap lines i and partition.
	    let partition = partition + 1
	    if (result == 0)
		let middle = partition
	    endif
	    if (i != partition)
		let str2 = getline(partition)
		call setline(i, str2)
		call setline(partition, str)
	    endif
	endif
	let i = i + 1
  endwhile

  " Now we have a pointer to the "middle" element, as far as partitioning
  " goes, which could be anywhere before the partition.  Make sure it is at
  " the end of the partition.
  if (middle != partition)
	let str = getline(middle)
	let str2 = getline(partition)
	call setline(middle, str2)
	call setline(partition, str)
  endif
  call <SID>SortR(a:start, partition - 1, a:cmp)
  call <SID>SortR(partition + 1, a:end, a:cmp)
endfunc

" To Sort a range of lines, pass the range to Sort() along with the name of a
" function that will compare two lines.
func! <SID>Sort(cmp) range
  call <SID>SortR(a:firstline, a:lastline, a:cmp)
endfunc

" Added to deal with internationalized version of diff, which returns a
" different string than "Files ... differ" or "Only in ... "

function! <SID>GetDiffStrings()
    " Check if we have the dynamic text string turned on.  If not, just return
    " what's set in the global variables

    if (g:DirDiffDynamicDiffText == 0)
        let s:DirDiffDiffOnlyLineCenter = g:DirDiffTextOnlyInCenter
        let s:DirDiffDiffOnlyLine = g:DirDiffTextOnlyIn
        let s:DirDiffDifferLine = g:DirDiffTextFiles
        let s:DirDiffDifferAndLine = g:DirDiffTextAnd
        let s:DirDiffDifferEndLine = g:DirDiffTextDiffer
        return
    endif

	let tmp1 = tempname()
	let tmp2 = tempname()
	let tmpdiff = tempname()

    " We need to pad the backslashes in order to make it match
    let tmp1rx = <SID>EscapeDirForRegex(tmp1)
    let tmp2rx = <SID>EscapeDirForRegex(tmp2)
    let tmpdiffrx = <SID>EscapeDirForRegex(tmpdiff)

	silent exe s:DirDiffMakeDirCmd . "\"" . tmp1 . "\""
	silent exe s:DirDiffMakeDirCmd . "\"" . tmp2 . "\""
	silent exe "!echo test > \"" . tmp1 . s:sep . "test" . "\""
	silent exe "!" . g:DirDiffLangString . "diff -r --brief \"" . tmp1 . "\" \"" . tmp2 . "\" > \"" . tmpdiff . "\""

	" Now get the result of that diff cmd
	silent exe "split ". tmpdiff
    "echo "First line: " . getline(1)
    "echo "tmp1: " . tmp1
    "echo "tmp1rx: " . tmp1rx
    let regex = '\(^.*\)' . tmp1rx . '\(.*\)' . "test"
	let s:DirDiffDiffOnlyLine = substitute( getline(1), regex, '\1', '')
	let s:DirDiffDiffOnlyLineCenter = substitute( getline(1), regex, '\2', '')
    "echo "DirDiff Only: " . s:DirDiffDiffOnlyLine

	bd

	" Now let's get the Differ string
    "echo "Getting the diff in GetDiffStrings"

	silent exe "!echo testdifferent > \"" . tmp2 . s:sep . "test" . "\""
	silent exe "!" . g:DirDiffLangString . "diff -r --brief \"" . tmp1 . "\" \"" . tmp2 . "\" > \"" . tmpdiff . "\""

	silent exe "split ". tmpdiff
	let s:DirDiffDifferLine = substitute( getline(1), tmp1rx . ".*$", "", '')
    " Note that the diff on cygwin may output '/' instead of '\' for the
    " separator, so we need to accomodate for both cases
    let andrx = "^.*" . tmp1rx . "[\\\/]test\\(.*\\)" . tmp2rx . "[\\\/]test.*$"
    let endrx = "^.*" . tmp1rx . "[\\\/]test.*" . tmp2rx . "[\\\/]test\\(.*$\\)"
    "echo "andrx : " . andrx
    "echo "endrx : " . endrx
	let s:DirDiffDifferAndLine = substitute( getline(1), andrx , "\\1", '')
    let s:DirDiffDifferEndLine = substitute( getline(1), endrx, "\\1", '')

	"echo "s:DirDiffDifferLine = " . s:DirDiffDifferLine
	"echo "s:DirDiffDifferAndLine = " . s:DirDiffDifferAndLine
	"echo "s:DirDiffDifferEndLine = " . s:DirDiffDifferEndLine

	q

	" Delete tmp files
    "echo "Deleting tmp files."

	call <SID>Delete(tmp1)
	call <SID>Delete(tmp2)
	call <SID>Delete(tmpdiff)

	"avoid get diff text again
	let g:DirDiffTextOnlyInCenter = s:DirDiffDiffOnlyLineCenter
	let g:DirDiffTextOnlyIn = s:DirDiffDiffOnlyLine
	let g:DirDiffTextFiles = s:DirDiffDifferLine
	let g:DirDiffTextAnd = s:DirDiffDifferAndLine
	let g:DirDiffTextDiffer = s:DirDiffDifferEndLine
	let g:DirDiffDynamicDiffText = 0

endfunction
