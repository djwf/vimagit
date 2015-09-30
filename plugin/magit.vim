scriptencoding utf-8

"if exists('g:loaded_magit') || !executable('git') || &cp
"  finish
"endif
"let g:loaded_magit = 1
" Initialisation {{{

" FIXME: find if there is a minimum vim version required
" if v:version < 703
" endif

let g:magit_unstaged_buffer_name = "magit-playground"

" s:set: helper function to set user definable variable
" param[in] var: variable to set
" param[in] default: default value if not already set by the user
" return: no
function! s:set(var, default)
	if !exists(a:var)
		if type(a:default)
			execute 'let' a:var '=' string(a:default)
		else
			execute 'let' a:var '=' a:default
		endif
	endif
endfunction

call s:set('g:magit_stage_file_mapping',        "F")
call s:set('g:magit_stage_hunk_mapping',        "S")
call s:set('g:magit_commit_mapping1',           "C")
call s:set('g:magit_commit_mapping2',           "CC")
call s:set('g:magit_commit_amend_mapping',      "CA")
call s:set('g:magit_commit_fixup_mapping',      "CF")
call s:set('g:magit_reload_mapping',            "R")
call s:set('g:magit_ignore_mapping',            "I")

call s:set('g:magit_enabled',               1)

" }}}

" {{{ Internal functions

" Section names
" These are used to beautify the magit buffer and to help for some block
" selection
let s:magit_staged_section=         'Staged changes'
let s:magit_unstaged_section=       'Unstaged changes'
let s:magit_commit_section_start=   'Commit message'
let s:magit_commit_section_end=     'Commit message end'
let s:magit_stash_section=          'Stash list'

" magit#underline: helper function to underline a string
" param[in] title: string to underline
" return a string composed of strlen(title) '='
function! magit#underline(title)
	return substitute(a:title, ".", "=", "g")
endfunction

" magit#strip: helper function to strip a string
" WARNING: it only works with monoline string
" param[in] string: string to strip
" return: stripped string
function! magit#strip(string)
	return substitute(a:string, '^\s*\(.\{-}\)\s*\n\=$', '\1', '')
endfunction

" magit#decorate_section: helper function to add decoration around section name
" INFO: this decoration is important for syntax AND for regex used in this
" script to delimit blocks
" param[in] string: string to decorate
" return: decorated string
function! magit#decorate_section(string)
	return '&@'.a:string.'@&'
endfunction

" magit#join_list: helper function to concatente a list of strings with newlines
" param[in] list: List to to concat
" return: concatenated list
function! magit#join_list(list)
	return join(a:list, "\n") . "\n"
endfunction

" magit#append_file: helper function to append to a file
" Version working with file *possibly* containing trailing newline
" param[in] file: filename to append
" param[in] lines: List of lines to append
function! magit#append_file(file, lines)
	let fcontents=readfile(a:file, 'b')
	if !empty(fcontents) && empty(fcontents[-1])
		call remove(fcontents, -1)
	endif
	call writefile(fcontents+a:lines, a:file, 'b')
endfunction

" magit#get_staged: this function writes in current buffer all staged files
" WARNING: this function writes in file, it should only be called through
" protected functions like magit#update_buffer
function! magit#get_staged()
	put =''
	put =magit#decorate_section(s:magit_staged_section)
	put =magit#decorate_section(magit#underline(s:magit_staged_section))
	put =''
	silent! read !git diff --staged --no-color
endfunction

" magit#get_unstaged: this function writes in current buffer all unstaged
" and untracked files
" WARNING: this function writes in file, it should only be called through
" protected functions like magit#update_buffer
function! magit#get_unstaged()
	put =''
	put =magit#decorate_section(s:magit_unstaged_section)
	put =magit#decorate_section(magit#underline(s:magit_unstaged_section))
	put =''

	silent! read !git diff --no-color
	silent! read !git ls-files --others --exclude-standard | while read -r i; do git diff --no-color -- /dev/null "$i"; done
endfunction

function! magit#get_stashes()
	silent! let stash_list=systemlist("git stash list")
	if ( v:shell_error != 0 )
		echoerr "Git error: " . stash_list
	endif

	if (!empty(stash_list))
		put =''
		put =magit#decorate_section(s:magit_stash_section)
		put =magit#decorate_section(magit#underline(s:magit_stash_section))
		put =''

		for stash in stash_list
			let stash_id=substitute(stash, '^\(stash@{\d\+}\):.*$', '\1', '')
			put =stash
			silent! execute "read !git stash show -p " . stash_id
		endfor
	endif
endfunction


" s:magit_commit_mode: global variable which states in which commit mode we are
" values are:
"       '': not in commit mode
"       'CC': normal commit mode, next commit command will create a new commit
"       'CA': amend commit mode, next commit command will ament current commit
"       'CF': fixup commit mode, it should not be a global state mode
let s:magit_commit_mode=''

" magit#get_commit_section: this function writes in current buffer the commit
" section. It is a commit message, depending on s:magit_commit_mode
" WARNING: this function writes in file, it should only be called through
" protected functions like magit#update_buffer
" param[in] s:magit_commit_mode: this function uses global commit mode
"       'CC': prepare a brand new commit message
"       'CA': get the last commit message
function! magit#get_commit_section()
	let commit_mode_str=""
	if ( s:magit_commit_mode == 'CC' )
		let commit_mode_str="normal"
	elseif ( s:magit_commit_mode == 'CA' )
		let commit_mode_str="amend"
	endif
	put =''
	put =magit#decorate_section(s:magit_commit_section_start)
	put =magit#decorate_section('Commit mode: '.commit_mode_str)
	put =magit#decorate_section(magit#underline(s:magit_commit_section_start))
	put =''

	silent! let git_dir=magit#strip(system("git rev-parse --git-dir"))
	if ( v:shell_error != 0 )
		echoerr "Git error: " . git_dir
	endif
	" refresh the COMMIT_EDITMSG file
	if ( s:magit_commit_mode == 'CC' )
		silent! call system("GIT_EDITOR=/bin/false git commit -e 2> /dev/null")
	elseif ( s:magit_commit_mode == 'CA' )
		silent! call system("GIT_EDITOR=/bin/false git commit --amend -e 2> /dev/null")
	endif
	let commit_msg=magit#join_list(filter(readfile(git_dir . '/COMMIT_EDITMSG'), 'v:val !~ "^#"'))
	put =commit_msg
	put =magit#decorate_section(s:magit_commit_section_end)
endfunction

" magit#search_block: helper function, to get a block of text, giving a start
" and multiple end pattern
" a "pattern parameter" is a List:
"   @[0]: end pattern regex
"   @[1]: number of line to exclude above (negative), below (positive) or none (0)
" param[in] start_pattern: start "pattern parameter", which will be search
" backward (cursor position is set to end of line before searching, to find the
" pattern if on the current line)
" param[in] end_pattern: list of end "pattern parameter". Each pattern is 
" searched in order. It'll choose the match with the minimum line number
" (smallest region search)
" param[in] upperlimit_pattern: regex of upper limit. If start_pattern line is
" inferior to upper_limit line, block is discarded
" return: a list.
"      @[0]: return status
"      @[1]: List of selected block lines
function! magit#search_block(start_pattern, end_pattern, upper_limit_pattern)
	let l:winview = winsaveview()

	let upper_limit=0
	if ( a:upper_limit_pattern != "" )
		let upper_limit=search(a:upper_limit_pattern, "bnW")
	endif

	" important if backward regex is at the beginning of the current line
	call cursor(0, 100)
	let start=search(a:start_pattern[0], "bW")
	if ( start == 0 )
		call winrestview(l:winview)
		return [1, ""]
	endif
	if ( start < upper_limit )
		call winrestview(l:winview)
		return [1, ""]
	endif
	let start+=a:start_pattern[1]

	let end=0
	let min=line('$')
	for end_p in a:end_pattern
		let curr_end=search(end_p[0], "nW")
		if ( curr_end != 0 && curr_end <= min )
			let end=curr_end + end_p[1]
			let min=curr_end
		endif
	endfor
	if ( end == 0 )
		call winrestview(l:winview)
		return [1, ""]
	endif

	let lines=getline(start, end)

	call winrestview(l:winview)
	return [0, lines]
endfunction

" Regular expressions used to select blocks
let s:diff_re  = '^diff --git'
let s:stash_re = '^stash@{\d\+}:'
let s:hunk_re  = '^@@ -\(\d\+\),\?\(\d*\) +\(\d\+\),\?\(\d*\) @@'
let s:bin_re   = '^Binary files '
let s:title_re = '^##\%([^#]\|\s\)\+##$'
let s:eof_re   = '\%$'

" magit#git_commit: commit staged stuff with message prepared in commit section
" param[in] mode: mode to commit
"       'CF': don't use commit section, just amend previous commit with staged
"       stuff, without modifying message
"       'CC': commit staged stuff with message in commit section to a brand new
"       commit
"       'CA': commit staged stuff with message in commit section amending last
"       commit
" return no
function! magit#git_commit(mode)
	if ( a:mode == 'CF' )
		silent let git_result=system("git commit --amend -C HEAD")
	else
		let commit_section_pat_start='^'.magit#decorate_section(s:magit_commit_section_start).'$'
		let commit_section_pat_end='^'.magit#decorate_section(s:magit_commit_section_end).'$'
		let [ret, commit_msg]=magit#search_block([commit_section_pat_start, +3], [ [commit_section_pat_end, -1] ], "")
		let amend_flag=""
		if ( a:mode == 'CA' )
			let amend_flag=" --amend "
		endif
		silent! let git_result=system("git commit " . amend_flag . " --file -", commit_msg)
	endif
	if ( v:shell_error != 0 )
		echoerr "Git error: " . git_result
	endif
endfunction

" magit#select_file: select the whole diff file, relative to the current
" cursor position
" nota: if the cursor is not in a diff file when the function is called, this
" function will fail
" return: a List
"         @[0]: return value
"         @[1]: List of lines containing the patch for the whole file
function! magit#select_file()
	return magit#search_block([s:diff_re, 0], [ [s:diff_re, -1], [s:stash_re, -1], [s:title_re, -2], [s:bin_re, 0], [ s:eof_re, 0 ] ], "")
endfunction

" magit#select_file_header: select the upper diff header, relative to the current
" cursor position
" nota: if the cursor is not in a diff file when the function is called, this
" function will fail
" return: a List
"         @[0]: return value
"         @[1]: List of lines containing the diff header
function! magit#select_file_header()
	return magit#search_block([s:diff_re, 0], [ [s:hunk_re, -1] ], "")
endfunction

" magit#select_hunk: select a hunk, from the current cursor position
" nota: if the cursor is not in a hunk when the function is called, this
" function will fail
" return: a List
"         @[0]: return value
"         @[1]: List of lines containing the hunk
function! magit#select_hunk()
	return magit#search_block([s:hunk_re, 0], [ [s:hunk_re, -1], [s:diff_re, -1], [s:stash_re, -1], [s:title_re, -2], [ s:eof_re, 0 ] ], s:diff_re)
endfunction

" magit#git_apply: helper function to stage a selection
" nota: when git fail (due to misformated patch for example), an error
" message is raised.
" param[in] selection: the text to stage. It must be a patch, i.e. a diff 
" header plus one or more hunks
" return: no
function! magit#git_apply(selection)
	let selection=magit#join_list(a:selection)
	silent let git_result=system("git apply --cached -", selection)
	if ( v:shell_error != 0 )
		echoerr "Git error: " . git_result
	endif
endfunction

" magit#git_unapply: helper function to unstage a selection
" nota: when git fail (due to misformated patch for example), an error
" message is raised.
" param[in] selection: the text to stage. It must be a patch, i.e. a diff 
" header plus one or more hunks
" return: no
function! magit#git_unapply(selection)
	silent let git_result=system("git apply --cached --reverse -", a:selection)
	if ( v:shell_error != 0 )
		echoerr "Git error: " . git_result
	endif
endfunction

" }}}

" {{{ User functions and commands

" magit#update_buffer: this function:
" 1. checks that current buffer is the wanted one
" 2. save window state (cursor position...)
" 3. delete buffer
" 4. fills with unstage stuff
" 5. restore window state
function! magit#update_buffer()
	if ( @% != g:magit_unstaged_buffer_name )
		echoerr "Not in magit buffer " . g:magit_unstaged_buffer_name . " but in " . @%
		return
	endif
	" FIXME: find a way to save folding state. According to help, this won't
	" help:
	" > This does not save fold information.
	" Playing with foldenable around does not help.
	" mkview does not help either.
	let l:winview = winsaveview()
	silent! execute "normal! ggdG"
	
	if ( s:magit_commit_mode != '' )
		call magit#get_commit_section()
	endif
	call magit#get_staged()
	call magit#get_unstaged()
	call magit#get_stashes()

	call winrestview(l:winview)

	if ( s:magit_commit_mode != '' )
		let commit_section_pat_start='^'.magit#decorate_section(s:magit_commit_section_start).'$'
		silent! let section_line=search(commit_section_pat_start, "w")
		silent! call cursor(section_line+3, 0)
	endif

endfunction

" magit#show_magit: prepare and show magit buffer
" it also set local mappings to magit buffer
function! magit#show_magit(orientation)
	vnew 
	setlocal buftype=nofile
	setlocal bufhidden=delete
	setlocal noswapfile
	setlocal foldmethod=syntax
	setlocal foldlevel=1
	setlocal filetype=gitdiff
	"setlocal readonly

	silent! execute "bdelete " . g:magit_unstaged_buffer_name
	execute "file " . g:magit_unstaged_buffer_name

	execute "nnoremap <buffer> <silent> " . g:magit_stage_file_mapping .   " :call magit#stage_file()<cr>"
	execute "nnoremap <buffer> <silent> " . g:magit_stage_hunk_mapping .   " :call magit#stage_hunk()<cr>"
	execute "nnoremap <buffer> <silent> " . g:magit_reload_mapping .       " :call magit#update_buffer()<cr>"
	execute "nnoremap <buffer> <silent> " . g:magit_commit_mapping1 .      " :call magit#commit_command('CC')<cr>"
	execute "nnoremap <buffer> <silent> " . g:magit_commit_mapping2 .      " :call magit#commit_command('CC')<cr>"
	execute "nnoremap <buffer> <silent> " . g:magit_commit_amend_mapping . " :call magit#commit_command('CA')<cr>"
	execute "nnoremap <buffer> <silent> " . g:magit_commit_fixup_mapping . " :call magit#commit_command('CF')<cr>"
	execute "nnoremap <buffer> <silent> " . g:magit_ignore_mapping .       " :call magit#ignore_file()<cr>"
	
	call magit#update_buffer()
	execute "normal! gg"
endfunction

" magit#get_section: helper function to get the current section, according to
" cursor position
" return: string of the current section, without decoration
function! magit#get_section()
	let section_line=search('^&@[a-zA-Z ]\+@&$', "bnW")
	return substitute(getline(section_line), '^&@\([a-zA-Z ]\+\)@&$', '\1', '')
endfunction

" magit#stage_hunk: this function stage a single hunk, from the current
" cursor position
" INFO: in unstaged section, it stages the hunk, and in staged section, it
" unstages the hunk
" return: no
function! magit#stage_hunk()
	let [ret, header] = magit#select_file_header()
	if ( ret != 0 )
		echoerr "Can't find diff header"
		return
	endif
	let [ret, hunk] = magit#select_hunk()
	if ( ret != 0 )
		echoerr "Not in a hunk region"
		return
	endif
	let section=magit#get_section()
	if ( section == s:magit_unstaged_section )
		call magit#git_apply(header + hunk)
	elseif ( section == s:magit_staged_section )
		call magit#git_unapply(header + hunk)
	else
		echoerr "Must be in \"".s:magit_unstaged_section."\" or \"".s:magit_staged_section."\" section"
	endif
	call magit#update_buffer()
endfunction

" magit#stage_file: this function stage a whole file, from the current
" cursor position
" INFO: in unstaged section, it stages the file, and in staged section, it
" unstages the file
" return: no
function! magit#stage_file()
	let [ret, selection] = magit#select_file()
	if ( ret != 0 )
		echoerr "Not in a file region"
		return
	endif
	let section=magit#get_section()
	if ( section == s:magit_unstaged_section )
		call magit#git_apply(selection)
	elseif ( section == s:magit_staged_section )
		call magit#git_unapply(selection)
	else
		echoerr "Must be in \"".s:magit_unstaged_section."\" or \"".s:magit_staged_section."\" section"
	endif
	call magit#update_buffer()
endfunction

" magit#ignore_file: this function add the file under cursor to .gitignore
" FIXME: git diff adds some strange characters to end of line
function! magit#ignore_file()
	let [ret, selection] = magit#select_file()
	if ( ret != 0 )
		echoerr "Not in a file region"
		return
	endif
	let ignore_file=""
	for line in selection
		if ( match(line, "^+++ ") != -1 )
			let ignore_file=magit#strip(substitute(line, '^+++ ./\(.*\)$', '\1', ''))
			break
		endif
	endfor
	if ( ignore_file == "" )
		echoerr "Can not find file to ignore"
		return
	endif
	let top_dir=magit#strip(system("git rev-parse --show-toplevel")) . "/"
	if ( v:shell_error != 0 )
		echoerr "Git error: " . top_dir
	endif
	call magit#append_file(top_dir . "/.gitignore", [ ignore_file ] )
	call magit#update_buffer()
endfunction

" magit#commit_command: entry function for commit mode
" INFO: it has a different effect if current section is commit section or not
" param[in] mode: commit mode
"   'CF': do not set global s:magit_commit_mode, directly call magit#git_commit
"   'CA'/'CF': if in commit section mode, call magit#git_commit, else just set
"   global state variable s:magit_commit_mode,
function! magit#commit_command(mode)
	let section=magit#get_section()
	if ( a:mode == 'CF' )
		call magit#git_commit(a:mode)
	else
		if ( section == s:magit_commit_section_start )
			if ( s:magit_commit_mode == '' )
				echoerr "Error, commit section should not be enabled"
				return
			endif
			" when we do commit, it is prefered ot commit the way we prepared it
			" (.i.e normal or amend), whatever we commit with CC or CA.
			call magit#git_commit(s:magit_commit_mode)
			let s:magit_commit_mode=''
		else
			let s:magit_commit_mode=a:mode
		endif
	endif
	call magit#update_buffer()
endfunction

command! Magit call magit#show_magit("v")

" }}}
