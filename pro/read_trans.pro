;+
;
; READ_TRANS
;
; Read in a photometric transformation file.
;
; INPUTS:
;  transfile  This gives the transformation information needed
;             to calibrate the raw photometry.  Normally there
;             is a different one of these for every night.
;
;             There need to be two lines per band.
;             FIRST line:  band name,  color name, transformation
;             equation coefficients (zero point, airmass, color
;             airmass*color, color^2)
;             SECOND line: errors in the transformation equation
;             coefficients
;
;     This is an example transfile:
;     M    M-T  -0.9990    0.1402     -0.1345    0.0000   0.0000
;               1.094E-02  5.037E-03  2.010E-03  0.0000   0.0000
;     T    M-T  -0.0061    0.0489     0.0266     0.0000   0.0000
;               6.782E-03  3.387E-03  1.374E-03  0.0000   0.0000
;     D    M-D  1.3251     0.1403     -0.0147    0.0000   0.0000
;               1.001E-02  5.472E-03  2.653E-02  0.0000   0.0000
;
;             If the transfile has chip information then it should
;             look like this:
;  1  G  G-R  -0.4089    0.1713   -0.1193   0.0000   0.0000
;              0.0040   -0.0000    0.0001   0.0000   0.0000
; 
;  2  G  G-R  -0.3617    0.1713   -0.1193   0.0000   0.0000
;              0.0039   -0.0000    0.0001   0.0000   0.0000
; 
;  3  G  G-R  -0.3457    0.1713   -0.1193   0.0000   0.0000
;              0.0039   -0.0000    0.0001   0.0000   0.0000
;
;  /silent    Don't print anything to the screen.
;  =logfile   The name of a logfile to write messages to.
;  /stp       Stop at the end of the program.
;
; OUTPUTS:
;  trans      The transformation structure.
;
; USAGE:
;  IDL>read_trans,'n1.trans',trans
;
; By D.Nidever  Feb.2013
;-

pro read_trans,transfile,trans,silent=silent,logfile=logfile,stp=stp

undefine,trans

if n_elements(transfile) eq 0 then begin
  print,'Syntax - read_trans,transfile,trans,silent=silent,logfile=logfile,stp=stp'
  return
endif

if file_test(transfile) eq 0 then begin
  print,transfile,' NOT FOUND'
  return
endif

; Logfile
if keyword_set(logfile) then logf=logfile else logf=-1


;# #####################################################
;# READ THE TRANSFORMATION FILE
;# Two lines per band.
;# First line:  band name,  color name, transformation equation coefficients
;# Second line: errors in the transformation equation coefficients

; If this has chip-specific transformations then the lines will be
; First line:  chip,  band name, color name, trans eqns.
; second line:  errors
;  1  G  G-R  -0.4089    0.1713   -0.1193   0.0000   0.0000
;              0.0040   -0.0000    0.0001   0.0000   0.0000
; 
;  2  G  G-R  -0.3617    0.1713   -0.1193   0.0000   0.0000
;              0.0039   -0.0000    0.0001   0.0000   0.0000
; 
;  3  G  G-R  -0.3457    0.1713   -0.1193   0.0000   0.0000
;              0.0039   -0.0000    0.0001   0.0000   0.0000

openr,unit,/get_lun,transfile

while (~EOF(unit)) do begin

  trans1 = {chip:-1,band:'',color:'',colband:'',colsign:0,zpterm:0.0d,amterm:0.0d,colterm:0.0d,$
            amcolterm:0.0d,colsqterm:0.0d,zptermsig:0.0d,amtermsig:0.0d,coltermsig:0.0d,$
            amcoltermsig:0.0d,colsqtermsig:0.0d}

  ; Reading in the transformation coefficients line
  line=''
  readf,unit,line

  ; Not a blank line
  if strtrim(line,2) ne '' and strmid(line,0,1) ne '#' then begin
    arr = strsplit(line,' ',/extract)
    narr = n_elements(arr)

    ; This has chip information
    isnum = valid_num(arr[0],chip)
    if (isnum eq 1) then begin
      trans1.chip = long(chip)
      arr = arr[1:*]
    endif

    trans1.band = arr[0]
    trans1.color = arr[1]
    trans1.zpterm = arr[2]
    trans1.amterm = arr[3]
    trans1.colterm = arr[4]
    trans1.amcolterm = arr[5]
    trans1.colsqterm = arr[6]

    ; Reading in the error line
    line2=''
    readf,unit,line2
    arr2 = strsplit(line2,' ',/extract)

    trans1.zptermsig = arr2[0]
    trans1.amtermsig = arr2[1]  
    trans1.coltermsig = arr2[2] 
    trans1.amcoltermsig = arr2[3]
    trans1.colsqtermsig = arr2[4]

    ; Add to final transformation structure
    push,trans,trans1

  endif

endwhile

close,unit
free_lun,unit

; No chip information, strip CHIP
gdchip = where(trans.chip ge 0,ngdchip)
if ngdchip eq 0 then begin
  oldtrans = trans
  trans = replicate({band:'',color:'',colband:'',colsign:0,zpterm:0.0d,amterm:0.0d,colterm:0.0d,$
            amcolterm:0.0d,colsqterm:0.0d,zptermsig:0.0d,amtermsig:0.0d,coltermsig:0.0d,$
            amcoltermsig:0.0d,colsqtermsig:0.0d},n_elements(trans))
  STRUCT_ASSIGN,oldtrans,trans
endif

ntrans = n_elements(trans)


; Figure out the colband and colsign for each band/chip
for i=0,ntrans-1 do begin

  band = strtrim(trans[i].band,2)

  col = strcompress(trans[i].color,/remove_all)

  ; Splitting up the two bands
  arr = strsplit(col,'-',/extract)

  ind = where(arr eq band,nind)

  ; colsign = 1 means band - colband
  if (ind[0] eq 0) then begin
    trans[i].colband = arr[1]
    trans[i].colsign = 1
  endif

  ; colsign = 2 means colband - band
  if (ind[0] eq 1) then begin
    trans[i].colband = arr[0]
    trans[i].colsign = 2
  endif

  if (ind[0] eq -1) then begin
    trans[i].colband = ''
    trans[i].colsign = -1
  endif

endfor


; Print the transformation equations
if not keyword_set(silent) then begin
  ; Chip information
  if tag_exist(trans,'CHIP') then begin
    printlog,logf,' TRANSFORMATION EQUATIONS'
    printlog,logf,'-------------------------------------------------------------------------'
    printlog,logf,'  CHIP   BAND   COLOR  ZERO-POINT  AIRMASS   COLOR     AIR*COL   COLOR^2 '
    printlog,logf,'-------------------------------------------------------------------------'
    for i=0,ntrans-1 do begin
      form1 = '(I4,A7,A10,F10.4,F10.4,F10.4,F10.4,F10.4)'
      printlog,logf,format=form1,trans[i].chip,'  '+trans[i].band,trans[i].color,trans[i].zpterm,trans[i].amterm,$
                        trans[i].colterm,trans[i].amcolterm,trans[i].colsqterm
      form2 = '(A21,F10.4,F10.4,F10.4,F10.4,F10.4)'
      printlog,logf,format=form2,'',trans[i].zptermsig,trans[i].amtermsig,trans[i].coltermsig,$
                        trans[i].amcoltermsig,trans[i].colsqtermsig
    end
    printlog,logf,'-------------------------------------------------------------------------'
    printlog,logf,''

  ; No chip information
  endif else begin
    printlog,logf,' TRANSFORMATION EQUATIONS'
    printlog,logf,'------------------------------------------------------------------'
    printlog,logf,' BAND   COLOR  ZERO-POINT  AIRMASS   COLOR     AIR*COL   COLOR^2 '
    printlog,logf,'------------------------------------------------------------------'
    for i=0,ntrans-1 do begin
      form = '(A-5,A8,F10.4,F10.4,F10.4,F10.4,F10.4)'
      printlog,logf,format=form,'  '+trans[i].band,trans[i].color,trans[i].zpterm,trans[i].amterm,$
                        trans[i].colterm,trans[i].amcolterm,trans[i].colsqterm
      printlog,logf,format=form,'','',trans[i].zptermsig,trans[i].amtermsig,trans[i].coltermsig,$
                        trans[i].amcoltermsig,trans[i].colsqtermsig
    end
    printlog,logf,'------------------------------------------------------------------'
    printlog,logf,''
  endelse
endif

if keyword_set(stp) then stop

end
