" QuickFixCurrentNumber.vim: Locate the quickfix item at the cursor position.
"
" DEPENDENCIES:
"   - ingo/err.vim autoload script
"
" Copyright: (C) 2013-2015 Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'.
"
" Maintainer:	Ingo Karkat <ingo@karkat.de>
"
" REVISION	DATE		REMARKS
"   1.11.007	11-Mar-2015	BUG: Script errors when jump mappings like ]q
"				are executed in a quickfix / location list. Need
"				to populate the bufferQflist property in the
"				returned result and tweak the check in
"				QuickFixCurrentNumber#Next(). Thanks to Enno
"				Nagel for reporting this.
"				Use ingo/err.vim for error reporting. Move the
"				beep in s:GotoIdx() into the mappings, to be
"				consistent with <Plug>(QuickFixCurrentNumberGo),
"				and have a clean separation.
"   1.10.006	08-Mar-2015	Add a:isFallbackToLast argument to fallback to
"				the last error location in case the cursor is
"				already behind all of them.
"   1.01.005	07-Feb-2015	Factor out
"				ingo#window#quickfix#TranslateVirtualColToByteCount()
"				into ingo-library.
"   1.00.004	19-Feb-2013	Don't print errors for g<C-q> mapping.
"   1.00.003	11-Feb-2013	Factor out common checks and errors to
"				s:CheckAndGetNumber().
"				Implement moving to next / previous error in
"				current buffer through
"				QuickFixCurrentNumber#Next().
"	002	09-Feb-2013	Split off autoload script and documentation.
"				Keep the existing (numbered) order when one item
"				doesn't have a line, or when there's equality in
"				columns.
"	001	08-Feb-2013	file creation

function! s:KeepOrder( i1, i2 )
    return a:i1.number > a:i2.number ? 1 : -1
endfunction
function! s:QflistSort( i1, i2 )
    if a:i1.lnum == 0 || a:i2.lnum == 0
	" One doesn't have a line, keep existing order.
	return s:KeepOrder(a:i1, a:i2)
    elseif a:i1.lnum == a:i2.lnum
	" Same line, compare columns.
	if a:i1.col == 0 || a:i2.col == 0
	    " One doesn't have a column, keep existing order.
	    return s:KeepOrder(a:i1, a:i2)
	elseif a:i1.vcol == a:i2.vcol
	    " Same column type, compare.
	    return a:i1.col == a:i2.col ? s:KeepOrder(a:i1, a:i2) : a:i1.col > a:i2.col ? 1 : -1
	else
	    " Different column type, translate the virtual column into the
	    " byte count.
	    let l:translatedCol = ingo#window#quickfix#TranslateVirtualColToByteCount(a:i1.vcol ? a:i1 : a:i2)
	    if a:i1.vcol
		return l:translatedCol == a:i2.col ? s:KeepOrder(a:i1, a:i2) : l:translatedCol > a:i2.col ? 1 : -1
	    else
		return a:i1.col == l:translatedCol ? s:KeepOrder(a:i1, a:i2) : a:i1.col > l:translatedCol ? 1 : -1
	    endif
	endif
    else
	return a:i1.lnum > a:i2.lnum ? 1 : -1
    endif
endfunction

function! s:GetBufferQflist( qflist )
    " Though the list is usually sorted, it is not necessarily (e.g. one can use
    " :caddexpr to add entries out-of-band).
    let l:idx = 0
    while l:idx < len(a:qflist)
	let a:qflist[l:idx].number = l:idx + 1
	let l:idx += 1
    endwhile

    return sort(filter(copy(a:qflist), 'v:val.bufnr ==' . bufnr('')), 's:QflistSort')
endfunction
function! s:GetNumber( qflist, isFallbackToLast )
    let l:bufferQflist = s:GetBufferQflist(a:qflist)
    let l:result = {'isEmpty': len(l:bufferQflist) == 0, 'idx': -1, 'nr': 0, 'isOnEntry': 0, 'bufferQflist': l:bufferQflist}

    for l:idx in range(len(l:bufferQflist))
	let l:item = l:result.bufferQflist[l:idx]
	if l:item.lnum < line('.')
	    continue    " Before current line (or line not specified).
	elseif l:item.lnum == line('.') && l:item.col == 0
	    " The column is not specified. Match entire line; the actual error
	    " could be anywhere.
	    let l:result.idx = l:idx
	    let l:result.nr = l:item.number
	    let l:result.isOnEntry = 1
	    return l:result
	elseif l:item.lnum == line('.') && l:item.col < (l:item.vcol ? vcol('.') : col('.'))
	    continue    " Before cursor on the current line.
	endif

	let l:result.idx = l:idx
	let l:result.nr = l:item.number
	let l:result.isOnEntry = (l:item.lnum == line('.') && l:item.col == (l:item.vcol ? vcol('.') : col('.')))
	return l:result
    endfor

    if a:isFallbackToLast && ! l:result.isEmpty
	let l:result.idx = len(l:bufferQflist) - 1
	let l:result.nr = l:bufferQflist[l:result.idx].number
    endif

    return l:result
endfunction


function! s:CheckAndGetNumber( isLocationList, isPrintErrors, isFallbackToLast )
    call ingo#err#Clear()

    if &l:buftype ==# 'quickfix'
	call ingo#err#Set('Already in quickfix')
	return {'nr': 0, 'bufferQflist': []}
    endif

    let l:result = s:GetNumber(a:isLocationList ? getloclist(0) : getqflist(), a:isFallbackToLast)
    if ! a:isPrintErrors
	return l:result
    endif

    if l:result.isEmpty
	call ingo#err#Set(a:isLocationList ? 'No location list' : 'No Errors')
    elseif l:result.nr == 0
	call ingo#err#Set('No more items')
    endif
    return l:result
endfunction
function! QuickFixCurrentNumber#Print( isLocationList )
    let l:nr = s:CheckAndGetNumber(a:isLocationList, 1, 0).nr
    if l:nr <= 0
	return 0
    endif

    let l:qflist = (a:isLocationList ? getloclist(0) : getqflist())
    echomsg printf('(%d of %d): %s', l:nr, len(l:qflist), get(l:qflist[l:nr - 1], 'text', ''))
    return 1
endfunction

function! QuickFixCurrentNumber#Go( isPrintErrors, isFallbackToLast, ... )
    let l:isLocationList = (a:0 ? a:1 : ! empty(getloclist(0)))
    let l:cmdPrefix = (l:isLocationList ? 'l' : 'c')
    let l:nr = s:CheckAndGetNumber(l:isLocationList, a:isPrintErrors, a:isFallbackToLast).nr
    if l:nr <= 0
	return 0
    endif

    let l:save_view = winsaveview()
    execute l:cmdPrefix . 'open'

    execute l:nr . l:cmdPrefix . 'first'
    " Above command jumps back to the buffer, and the selected error location. Restore the original position.
    call winrestview(l:save_view)

    execute l:cmdPrefix . 'open'
    return 1
endfunction


function! s:GotoIdx( isLocationList, bufferQflist, idx )
    if a:idx < 0 || a:idx >= len(a:bufferQflist)
	return 0
    endif

    let l:cmdPrefix = (a:isLocationList ? 'l' : 'c')
    execute a:bufferQflist[a:idx].number . l:cmdPrefix . 'first'
    return 1
endfunction

function! QuickFixCurrentNumber#Next( count, isLocationList, isBackward )
    let l:result = s:CheckAndGetNumber(a:isLocationList, 0, 0)
    if l:result.nr == 0 && len(l:result.bufferQflist) == 0
	return 0
    endif

    if a:isBackward
	if l:result.nr == 0
	    " There are no more matches after the cursor, so the last match in
	    " the buffer must be the one before the cursor.
	    let l:nextIdx = len(l:result.bufferQflist) - a:count
	else
	    let l:nextIdx = l:result.idx - a:count
	endif
    else
	let l:nextIdx = l:result.idx + a:count - (l:result.isOnEntry ? 0 : 1)
    endif

    return s:GotoIdx(a:isLocationList, l:result.bufferQflist, l:nextIdx)
endfunction
function! QuickFixCurrentNumber#Border( count, isLocationList, isEnd )
    if &l:buftype ==# 'quickfix'
	call ingo#err#Set('Already in quickfix')
	return 0
    endif

    let l:bufferQflist = s:GetBufferQflist(a:isLocationList ? getloclist(0) : getqflist())
    let l:idx = (a:isEnd ? len(l:bufferQflist) - a:count : a:count - 1)

    call ingo#err#Clear()
    return s:GotoIdx(a:isLocationList, l:bufferQflist, l:idx)
endfunction

" vim: set ts=8 sts=4 sw=4 noexpandtab ff=unix fdm=syntax :
