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

" Run the diff command asynchronously via NeoVim's jobstart(), instead of
" the classic blocking ":!cmd" call.  Defaults to on under NeoVim, and is
" simply ignored (always synchronous) under classic Vim, which has no
" equivalent async job API usable here.
if !exists("g:DirDiffAsync")
    let g:DirDiffAsync = has('nvim')
endif
" Maximum number of concurrent diff jobs to run when fanning the
" comparison out across the top-level entries of the two directories
" (NeoVim only).  Clamped to the range [1, 64] when actually used.  A
" value of 1 (the default) just runs a single diff job asynchronously,
" without any fan-out.
if !exists("g:DirDiffMaxJobs")
    let g:DirDiffMaxJobs = 1
endif
" Optional per-job timeout, in milliseconds.  0 (the default) means no
" timeout is enforced.
if !exists("g:DirDiffJobTimeout")
    let g:DirDiffJobTimeout = 0
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
" Progress counters, also used to know when every job is done.
let s:DirDiffJobsTotal = 0
let s:DirDiffJobsDone = 0
" Context shared by the queue pump and the job callbacks; set once per
" DirDiff() invocation, before any job is started.
let s:DirDiffJobMaxJobs = 1
let s:DirDiffJobDirA = ""
let s:DirDiffJobDirB = ""
let s:DirDiffJobCmdArg = ""
" Buffer number of the live result buffer, built up front by
" s:DirDiffBuildSkeleton() and streamed into progressively by
" s:DirDiffStreamAppend() as job output arrives -- the one and only
" buffer used by the whole async path, whether it ends up running a
" single diff job (g:DirDiffMaxJobs <= 1, no fan-out) or several
" concurrent ones (fan-out).  g:DirDiffMaxJobs only controls
" parallelism; streaming always applies the same way regardless.  -1
" when none is active.
let s:DirDiffStatusBufNr = -1
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
" Minimal seam around jobstart()/jobstop() so the rest of the plugin
" doesn't need to sprinkle has('nvim') checks everywhere.  Returns -1
" when async execution isn't available/enabled, the same way callers
" already treat a jobstart() failure.
"
" Mirrors the &shell swap that <SID>DirDiffExec() does for the
" synchronous path: NeoVim resolves &shell/&shellcmdflag synchronously
" at jobstart() call time to build the process argv, so a save/restore
" done strictly around the jobstart() call (not around the job's whole
" lifetime) is enough to honour g:DirDiffForceShell for async jobs too.
function! s:JobStart(cmd, callbacks) abort
    if !g:DirDiffAsync || !has('nvim')
        return -1
    endif
    let shellChanged = (g:DirDiffForceShell != "")
    if shellChanged
        let shell_save = &shell
        let &shell = g:DirDiffForceShell
    endif
    " jobstart() can throw synchronously (eg. E903 if &shell itself points
    " to a nonexistent executable); guard with try/finally so &shell is
    " always restored, and fold that failure into the same "-1 = could
    " not start" contract the rest of the plugin already handles.
    let jobId = -1
    try
        let jobId = jobstart(a:cmd, a:callbacks)
    catch
        let jobId = -1
    finally
        if shellChanged
            let &shell = shell_save
        endif
    endtry
    return jobId
endfunction

function! s:JobStop(id) abort
    if a:id > 0
        silent! call jobstop(a:id)
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
    " themselves and no-op (see s:DirDiffOnJobExit()).
    let s:DirDiffGeneration = s:DirDiffGeneration + 1
    let myGeneration = s:DirDiffGeneration

    let s:FilenameDiffWindow = tempname()
    " Constructs the diff command-line arguments
    let cmdarg = s:BuildDiffCmdArg()

    if (!g:DirDiffAsync || !has('nvim'))
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

    " ---- Asynchronous path (NeoVim only) ----
    let s:DirDiffJobQueue = []
    let s:DirDiffActiveJobs = []
    let s:DirDiffJobsTotal = 0
    let s:DirDiffJobsDone = 0
    let s:DirDiffJobDirA = DirDiffAbsSrcA
    let s:DirDiffJobDirB = DirDiffAbsSrcB
    let s:DirDiffJobCmdArg = cmdarg
    let s:DirDiffJobMaxJobs = max([1, min([64, g:DirDiffMaxJobs])])

    " Every async run -- whether it ends up running a single diff job
    " or fans out across several -- builds the final buffer's full UI
    " shell immediately and streams result lines into it as job output
    " arrives (see s:DirDiffBuildSkeleton()/s:DirDiffStreamAppend()
    " below, and s:DirDiffPumpQueue()'s on_stdout handling).
    " g:DirDiffMaxJobs only controls how many diff processes may run
    " concurrently; it never affects how promptly results show up.
    call s:DirDiffBuildSkeleton(DirDiffAbsSrcA, DirDiffAbsSrcB, cmdarg)

    if (s:DirDiffJobMaxJobs <= 1)
        " No fan-out: a single job runs the whole comparison (still
        " "-r" recursive over the entire tree being compared), just
        " non-blocking, with its stdout streamed into the skeleton
        " line-by-line exactly like a fan-out sub-job's output would
        " be.
        let cmd = g:DirDiffLangString . "diff" . cmdarg . " \"".DirDiffAbsSrcA."\" \"".DirDiffAbsSrcB."\""
        call s:DirDiffQueueJob(cmd, DirDiffAbsSrcA." <-> ".DirDiffAbsSrcB, myGeneration)
        let s:DirDiffJobsTotal = 1
        call s:DirDiffPumpQueue(myGeneration)
    else
        " Fan-out: partition the comparison across the top-level
        " entries of both directories so several diff jobs can run
        " concurrently; "only in" entries are shown immediately, and
        " each sub-job's own output streams in the same way as above.
        call s:DirDiffDispatchFanOut(DirDiffAbsSrcA, DirDiffAbsSrcB, cmdarg, myGeneration)
    endif
endfunction

" Builds the diff command-line arguments (everything except the two paths
" being compared) from the plugin's global options.  Shared by the
" single-job synchronous/async path and by every fan-out sub-job, so
" :ChangeExcludes/:ChangeIgnore/:ChangeArguments keep applying everywhere.
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
    return "Diffing... " . s:DirDiffJobsDone . "/" . s:DirDiffJobsTotal . " lots termines"
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
    call append(3, "Options: 'u'=update,'x'=set excludes,'i'=set ignore,'a'=set args, 'h'=hex mode, 'w'=wrap mode")
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
    call add(headerLines, "Options: 'u'=update,'x'=set excludes,'i'=set ignore,'a'=set args, 'h'=hex mode, 'w'=wrap mode")
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
    if !empty(a:lines)
        " Insert right above the trailing progress line, so new
        " entries land right after the last one already shown, in
        " arrival order -- no full re-sort/rebuild happens here, see
        " s:DirDiffFinishStreaming() for the single sort pass done
        " once every job is done.
        call appendbufline(s:DirDiffStatusBufNr, nvim_buf_line_count(s:DirDiffStatusBufNr) - 1, a:lines)
    endif
    call setbufline(s:DirDiffStatusBufNr, '$', s:DirDiffProgressText())
    call setbufvar(s:DirDiffStatusBufNr, '&modifiable', 0)
    call setbufvar(s:DirDiffStatusBufNr, '&modified', 0)

    " The visual refresh (window switch + :redraw) is the expensive
    " part -- a full synchronous screen repaint plus a window lookup/
    " switch -- so it's only done at most once every
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

    let savedWin = win_getid()
    call <SID>GotoDiffWindow()
    call win_gotoid(savedWin)
    redraw
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
    let savedWin = win_getid()
    call <SID>GotoDiffWindow()

    " A line the user already opened while jobs were still streaming in
    " may still carry the "==> " highlight marker; strip it before the
    " final sort below, since that marker would otherwise skew the
    " alphabetical ordering of otherwise-identical entries (a bare "="
    " does not collate the same way as the normal 4-space indent).
    if exists('b:currentDiff')
        call <SID>DeHighlightLine()
    endif

    setlocal modifiable
    " The trailing progress line has done its job; every job is done.
    $delete _
    setlocal nomodifiable
    setlocal nomodified

    if line('$') <= s:DirDiffFirstDiffLine
        " Nothing was ever streamed in (no "only in" entries, every
        " common entry diffed identical): behave like the synchronous
        " path and don't leave a stray, empty result buffer behind.
        call win_gotoid(savedWin)
        silent! execute "bwipeout! " . bufNr
        let s:DirDiffStatusBufNr = -1
        redraw | echom "diff found no differences - directories match."
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
    0

    call win_gotoid(savedWin)

    " Open the first diff now that every entry is in and sorted, same
    " as s:DirDiffFinalize() does for the classic synchronous path --
    " never before the sort, and only once per run.
    call <SID>DirDiffNext()
    redraw
endfunction

" Adds a unit of work (a complete "diff ..." shell command comparing two
" paths) to the pending job queue.  "desc" is only used for
" progress/error reporting.
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
        let jobId = s:JobStart(work.cmd, {'on_stdout': OnStdout, 'on_exit': OnExit})
        if jobId > 0
            call add(s:DirDiffActiveJobs, jobId)
            if g:DirDiffJobTimeout > 0
                call timer_start(g:DirDiffJobTimeout, {-> s:JobStop(jobId)})
            endif
        else
            " Could not even start the job; treat it as an immediate
            " error so the overall run doesn't hang forever.
            let s:DirDiffJobsDone = s:DirDiffJobsDone + 1
            let errLine = s:DirDiffTransformLine("[ERREUR] comparaison impossible : " . work.desc . " (demarrage du job echoue)", s:DirDiffJobDirA, s:DirDiffJobDirB)
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
        let transformed = map(chunk, 's:DirDiffTransformLine(v:val, s:DirDiffJobDirA, s:DirDiffJobDirB)')
        call s:DirDiffStreamAppend(transformed)
    endif
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
    " silently swallowing them.
    if a:data != 0 && a:data != 1
        call add(lines, "[ERREUR] comparaison impossible : " . a:desc . " (code " . a:data . ")")
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

" Fans the comparison out across the top-level entries of the two
" directories: entries present on both sides and that are directories on
" both sides, as well as entries present on both sides that are files,
" each become one queued diff job (further recursion into subdirectories
" happens inside that sub-diff thanks to "-r").  Entries that only exist
" on one side are resolved immediately, without spawning anything, by
" synthesizing the same "Only in ..." line that "diff --brief" itself
" would have produced.
function! s:DirDiffDispatchFanOut(dirA, dirB, cmdarg, generation) abort
    let entriesA = readdir(a:dirA)
    let entriesB = readdir(a:dirB)

    let setA = {}
    for name in entriesA
        let setA[name] = 1
    endfor
    let setB = {}
    for name in entriesB
        let setB[name] = 1
    endfor

    let onlyA = filter(copy(entriesA), '!has_key(setB, v:val)')
    let onlyB = filter(copy(entriesB), '!has_key(setA, v:val)')
    let common = filter(copy(entriesA), 'has_key(setB, v:val)')

    let commonDirs = []
    let commonFiles = []
    for name in common
        if isdirectory(a:dirA . s:sep . name) && isdirectory(a:dirB . s:sep . name)
            call add(commonDirs, name)
        else
            call add(commonFiles, name)
        endif
    endfor

    " Entries that only exist on one side don't need a diff job: we
    " already have everything required to synthesize the exact "Only in
    " ..." line diff --brief itself would output for a root-level
    " entry.  Collect them now; they're shown right away, below, before
    " any job has even started.
    let onlyLines = []
    for name in onlyA
        call add(onlyLines, s:DirDiffDiffOnlyLine . a:dirA . s:DirDiffDiffOnlyLineCenter . name)
    endfor
    for name in onlyB
        call add(onlyLines, s:DirDiffDiffOnlyLine . a:dirB . s:DirDiffDiffOnlyLineCenter . name)
    endfor

    " Each common directory gets its own job ("-r" in cmdarg makes diff
    " recurse into it).  Common files are also queued one job per entry,
    " rather than batched into a single shell invocation chaining several
    " "diff" calls: cmd.exe, PowerShell and POSIX shells don't agree on an
    " unconditional command separator, and "&&" would wrongly stop a
    " batch early anyway on GNU diff's "exit code 1 = differences found".
    " One job per entry is the simplest option that's correct on every
    " platform; concurrency is still bounded by g:DirDiffMaxJobs.
    for name in commonDirs + commonFiles
        let pathA = a:dirA . s:sep . name
        let pathB = a:dirB . s:sep . name
        let cmd = g:DirDiffLangString . "diff" . a:cmdarg . " \"" . pathA . "\" \"" . pathB . "\""
        call s:DirDiffQueueJob(cmd, pathA, a:generation)
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
                silent exec "bd ".bufnr(previousFile)
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
                silent exec "bd ".bufnr(previousFileA)

                call <SID>Drop(previousFileB)
                silent exec "edit ".s:FilenameB
                diffthis
                silent exec "bd ".bufnr(previousFileB)
            else
                let previousFile = (s:LastMode == "A") ? previousFileA : previousFileB
                call <SID>Drop(previousFile)
                silent exec "edit ".s:FilenameB
                silent exec "bd ".bufnr(previousFile)
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
