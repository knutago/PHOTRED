;+
;
; DAOMATCH
;
; This matches stars and finds the transformations using
; MATCHSTARS.PRO (originally DAOMATCH was used) and then
; combining them with DAOMASTER.  INputs need to be ALS files.
;
; INPUTS:
;  files     Array of ALS files,  The first file will be used
;            as the reference.
;  =maxshift Constraints on the initial X/Y shifts.
;  /verbose  Verbose output
;  /stp      Stop at the end of the program
;  =hi       Not used anymore.
;
; OUTPUTS:
;  An MCH, TFR and RAW file with basename of the first file.
;  =error    The error message if one occurred.
;
; USAGE:
;  IDL>daomatch,['obj1034_1.als','obj1035_1.als','obj1036_1.als']
;
; Add options to freeze the scale and/or rotation.
; 
; By D. Nidever   December 2006
;-

pro daomatch_dummy
FORWARD_FUNCTION test_trans
end

;---------------------------------------------------------------

function test_trans,trans

; This function tests if a transformation equation from
; daomatch is good or not.  The scale should be nearly 1.0
; and the rotation should be near 0.
;
; Return value:
;  1  Good
;  0  Bad
; -1  Fail
;

test = -1

if n_elements(trans) eq 0 then return,-1

; The test mainly looks at the rotation/scale values
; and not the xoff/yoff values.

sz = size(trans)
if sz[0] ne 2 or sz[1] ne 2 or sz[2] ne 6 then return,-1


xoff = (reform(trans[1,0]))(0)
yoff = (reform(trans[1,1]))(0)
c = (reform(trans[1,2]))(0)
e = (reform(trans[1,3]))(0)
d = (reform(trans[1,4]))(0) 
f = (reform(trans[1,5]))(0)
; from ccdpck.txt
;              x(1) = A + C*x(n) + E*y(n)
;              y(1) = B + D*x(n) + F*y(n)

; C=F~1 and D=E~0
test = 1
if abs(c-f) gt 0.1 then test=0
if abs(d-e) gt 0.1 then test=0
if abs(c-1.0) gt 0.1 then test=0
if abs(e) gt 0.1 then test=0

return,test

end

;---------------------------------------------------------------

pro daomatch,files,stp=stp,verbose=verbose,hi=hi,logfile=logfile,error=error,$
             maxshift=maxshift

t0 = systime(1)

undefine,error

nfiles = n_elements(files)
if nfiles eq 0 then begin
  print,'Syntax - daomatch,files,stp=stp,verbose=verbose'
  error = 'Not enough inputs'
  return
end

; Logfile
if keyword_set(logfile) then logf=logfile else logf=-1

; Only one file, can't match
if nfiles eq 1 then begin
  printlog,logf,'ONLY ONE FILE INPUT.  NEED AT *LEAST* TWO'
  error = 'ONLY ONE FILE INPUT.  NEED AT *LEAST* TWO'
  return
endif

; Compile MATCHSTARS.PRO
RESOLVE_ROUTINE,'matchstars',/compile_full_file

; Current directory
CD,current=curdir

dir = FILE_DIRNAME(files[0])
CD,dir

files2 = FILE_BASENAME(files,'.als')

; Remove the output files
FILE_DELETE,files2[0]+'.mch',/allow_nonexistent
FILE_DELETE,files2[0]+'.raw',/allow_nonexistent
FILE_DELETE,files2[0]+'.tfr',/allow_nonexistent

undefine,mchfinal

; Check that the reference file exists
test = FILE_TEST(files[0])
if (test eq 0) then begin
  printlog,logf,'REFERENCE FILE ',files[0],' NOT FOUND'
  error = 'REFERENCE FILE '+files[0]+' NOT FOUND'
  return
endif

; Load the reference data
LOADALS,files[0],refals,count=count
if (count lt 1) then begin
  printlog,logf,'PROBLEM LOADING ',files[0]
  error = 'PROBLEM LOADING '+files[0]
  return
endif


;; Get initial guess for X/Y shifts from WCS
;if keyword_set(initwcs) then begin
;  fitsfiles = file_basename(files,'.als')+'.fits'
;  if total(file_test(fitsfiles)) eq nfiles then begin
;    raarr = dblarr(nfiles) & decarr=dblarr(nfiles)
;    getpixscale,fitsfiles[0],pixscale
;    for i=0,nfiles-1 do begin
;      head = headfits(fitsfiles[i])
;      head_xyad,head,0,0,a,d,/deg
;      raarr[i]=a & decarr[i]=d
;   endfor
;    initwcs_xoff = (raarr-raarr[0])*3600*cos(decarr[0]/!radeg)/pixscale
;    initwcs_yoff = (decarr-decarr[0])*3600/pixscale
;    print,'Initial offsets from WCS'
;    for i=0,nfiles-1 do print,files[i],initwcs_xoff[i],initwcs_yoff[i]
;stop
;
;  endif else print,'Not all FITS files found'
;endif


format = '(A2,A-30,A1,2F10.2,4F10.5,2F10.3)'
newline = STRING("'",files[0],"'",0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, format=format)
PUSH,mchfinal,newline



if keyword_set(verbose) then $
  printlog,logf,'Initial Transformations:'

; Printing the first line
if keyword_set(verbose) then $
  printlog,logf,format='(A-20,2F10.4,4F12.8)',files[0], 0.0, 0.0, 1.0, 0.0, 0.0, 1.0



; Run DAOMATCH for each pair (N-1 times)
for i=1,nfiles-1 do begin

  undefine,als,alshead,trans,ind1,ind2,count

  ; Check that the file exists
  test = FILE_TEST(files[i])
  if (test eq 0) then begin
    printlog,logf,'FILE ',files[i],' NOT FOUND'
    error = 'FILE '+files[i]+' NOT FOUND'
    return
  endif

  ; Load the current data
  LOADALS,files[i],als,alshead,count=count
  if (count lt 1) then begin
    printlog,logf,'PROBLEM LOADING ',files[i]
    error = 'PROBLEM LOADING '+files[i]
    return
  endif


  ; Getting FRAD
  headarr = strsplit(alshead[1],' ',/extract)
  frad = float(first_el(headarr,/last))

  ; Make CHI, SHARP and ERR cuts here

  ; CUTS for REFALS
  gdref = where(abs(refals.sharp) lt 1.0 and refals.chi lt 2.0 and refals.mag lt 50.0 and $
                refals.err lt 0.2,ngdref)
  if (ngdref lt 100) then begin
    gdref = where(abs(refals.sharp) lt 1.5 and refals.chi lt 3.0 and refals.mag lt 50.0 and $
                  refals.err lt 0.5,ngdref)
  endif
  if (ngdref lt 100) then begin
    gdref = where(abs(refals.sharp) lt 1.5 and refals.chi lt 3.0 and refals.mag lt 50.0 and $
                  refals.err lt 1.0,ngdref)
  endif
  if (ngdref eq 0) then begin
    print,'NO good reference stars '+files[0]
    error = 'NO good reference stars '+files[0]
    return
  endif
  ; Cuts for ALS
  gdals = where(abs(als.sharp) lt 1.0 and als.chi lt 2.0 and als.mag lt 50.0 and $
                als.err lt 0.2,ngdals)
  if (ngdals lt 100) then begin
    gdals = where(abs(als.sharp) lt 1.5 and als.chi lt 3.0 and als.mag lt 50.0 and $
                  als.err lt 0.5,ngdals)
  endif
  if (ngdals lt 100) then begin
    gdals = where(abs(als.sharp) lt 1.5 and als.chi lt 3.0 and als.mag lt 50.0 and $
                  als.err lt 1.0,ngdals)
  endif
  if (ngdals eq 0) then begin
    print,'NO good stars for '+files[i]
    error = 'NO good stars for '+files[i]
    return
  endif

  ; Match stars
  ;MATCHSTARS,refals.x,refals.y,als.x,als.y,ind1,ind2,trans,count=count,/silent
  MATCHSTARS,refals[gdref].x,refals[gdref].y,als[gdals].x,als[gdals].y,ind1,ind2,trans,count=count,/silent

  ; No good matches, try srcmatch with "small" shifts
  if (count lt 1) then begin
    SRCMATCH,refals[gdref].x,refals[gdref].y,als[gdals].x,als[gdals].y,100,ind1a,ind2a,count=count1
    if count1 gt 0 then begin
      xdiff1 = refals[gdref[ind1a]].x-als[gdals[ind2a]].x
      ydiff1 = refals[gdref[ind1a]].y-als[gdals[ind2a]].y
      xmed1 = median(xdiff1)
      ymed1 = median(ydiff1)
      ; redo the search
      SRCMATCH,refals[gdref].x,refals[gdref].y,als[gdals].x+xmed1,als[gdals].y+ymed1,20,ind1,ind2,count=count
      xdiff = refals[gdref[ind1]].x-als[gdals[ind2]].x
      ydiff = refals[gdref[ind1]].y-als[gdals[ind2]].y
      xmed = median(xdiff)
      ymed = median(ydiff)
      trans = [xmed, ymed, 1.0, 0.0, 0.0, 1.0]
    endif
  endif

  ; No good match
  if (count lt 1) then begin
    printlog,logf,'NO MATCHES.  Using XSHIFT=YSHIFT=ROTATION=0'
    trans = [0.0, 0.0, 1.0, 0.0, 0.0, 1.0]
  endif

  ; Shift too large
  if keyword_set(maxshift) then begin
    if max(abs(trans[0:1])) gt maxshift then begin
      printlog,logf,'SHIFTS TOO LARGE. ',strtrim(trans[0:1],2),' > ',strtrim(maxshift,2),$
                    ' Using XSHIFT=YSHIFT=ROTATION=0'
      trans = [0.0, 0.0, 1.0, 0.0, 0.0, 1.0]
    endif
  endif

  ; The output is:
  ; filename, xshift, yshift, 4 trans, FRAD (from als file), 0.0
  format = '(A2,A-30,A1,2F10.2,4F10.5,2F10.3)'
  newline = STRING("'",files[i],"'",trans, frad, 0.0, format=format)
  PUSH,mchfinal,newline

  ; Printing the transformation
  if keyword_set(verbose) then $
    printlog,logf,format='(A-20,2F10.4,4F12.8)',files[i],trans

  ;stop

endfor  ; ALS file loop


; Writing the final mchfile
WRITELINE,files2[0]+'.mch',mchfinal

;stop



;#####################
; Running DAOMASTER
;#####################

; DAOMASTER has problems with files that have extra dots in them 
; (i.e. F1.obj1123_1.mch).
; Do everything with a temporary file, then rename the output files
; at the end.
;tempbase = MAKETEMP('temp','')
tempbase = FILE_BASENAME(MKTEMP('temp'))
FILE_DELETE,tempbase,/allow       ; remove empty file
tempbase = REPSTR(tempbase,'.')   ; remove the dot
tempmch = tempbase+'.mch'
FILE_COPY,files2[0]+'.mch',tempmch,/overwrite,/allow

; Make the DAOMASTER script
;--------------------------
undefine,cmdlines
PUSH,cmdlines,'#!/bin/csh'
PUSH,cmdlines,'set input=${1}'
PUSH,cmdlines,'daomaster << DONE'
PUSH,cmdlines,'${input}.mch'
PUSH,cmdlines,'1,1,1'
PUSH,cmdlines,'99.'
PUSH,cmdlines,'6'
PUSH,cmdlines,'10'
PUSH,cmdlines,'5'
PUSH,cmdlines,'4'
PUSH,cmdlines,'3'
PUSH,cmdlines,'2'
PUSH,cmdlines,'1'
PUSH,cmdlines,'1'
PUSH,cmdlines,'1'
PUSH,cmdlines,'1'
PUSH,cmdlines,'0'
PUSH,cmdlines,'y'
PUSH,cmdlines,'n'
PUSH,cmdlines,'n'
PUSH,cmdlines,'y'
PUSH,cmdlines,''
PUSH,cmdlines,'y'
PUSH,cmdlines,''
PUSH,cmdlines,''
PUSH,cmdlines,'y'
PUSH,cmdlines,''
PUSH,cmdlines,'n'
PUSH,cmdlines,'n'
PUSH,cmdlines,'DONE'
;tempscript = MAKETEMP('daomaster','.sh')
tempscript = MKTEMP('daomaster')   ; absolute filename
WRITELINE,tempscript,cmdlines
FILE_CHMOD,tempscript,'755'o

; Run DAOMASTER
;---------------
;cmd2 = '/net/home/dln5q/bin/daomaster.sh '+files2[0]
;cmd2 = './daomaster.sh '+tempbase
cmd2 = tempscript+' '+tempbase
SPAWN,cmd2,out2,errout2


; Remove temporary DAOMASTER script
;-----------------------------------
FILE_DELETE,tempscript,/allow_non


; Rename the outputs
;-------------------
; MCH file
mchfile = FILE_SEARCH(tempbase+'.mch',count=nmchfile)
if (nmchfile gt 0) then begin
  FILE_COPY,mchfile[0],files2[0]+'.mch',/overwrite,/allow
  FILE_DELETE,mchfile,/allow
endif else begin
  printlog,logf,'NO FINAL MCH FILE'
  error = 'NO FINAL MCH FILE'
  return
endelse
; TFR file
tfrfile = FILE_SEARCH(tempbase+'.tfr',count=ntfrfile)
if (ntfrfile gt 0) then begin
  FILE_COPY,tfrfile[0],files2[0]+'.tfr',/overwrite,/allow
  FILE_DELETE,tfrfile,/allow
endif else begin
  printlog,logf,'NO FINAL TFR FILE'
  error = 'NO FINAL TFR FILE'
  return
endelse
; RAW file
rawfile = FILE_SEARCH(tempbase+'.raw',count=nrawfile)
if (nrawfile gt 0) then begin
  FILE_COPY,rawfile[0],files2[0]+'.raw',/overwrite,/allow
  FILE_DELETE,rawfile,/allow
endif else begin
  printlog,logf,'NO FINAL RAW FILE'
  error = 'NO FINAL RAW FILE'
  return
endelse

; Were there any errors
if (errout2[0] ne '') then begin
  printlog,logf,'DAOMASTER.SH ERROR'
  printlog,logf,errout2
  error = errout2
  return
endif


; Print out the final transformations
if keyword_set(verbose) then begin
  LOADMCH,files2[0]+'.mch',files,trans
  nfiles = n_elements(files)
  printlog,logf,''
  printlog,logf,'Final DAOMASTER Transformations:'
  for i=0,nfiles-1 do begin
    printlog,logf,format='(A-20,2F10.4,4F12.8)',files[i],transpose(trans[i,*])
  end
endif


; Back to the original directory
CD,curdir

if keyword_set(stp) then stop

end