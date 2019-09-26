#!/bin/bash

export WORKFILE=""
export CURLIN=1
export SEARCHPAT=""
export DEBUGMODE=off
export TMPF1=/tmp/$$.1
export MODIFIED=false

trap 'echo ^c cleanup;/bin/rm -f $TMP1;exit' SIGINT SIGQUIT
export BUFFID=0
export BUFFERFN=()
export BUFF=()
# To avoid problems with sub-shells, we will use 'RETVAL' as the common
# way to return values from called functions.
RETVAL=""

function errormsg()
{
    TMPV="$@"
    >&2 echo "MSG>>> $TMPV"
}


function bermchar()
{
    # This function removes the need for external program sed for case of "sed 's/pat//g'"
    # It removes all cases of "$2" from "$1"
    local T1 C1 i NEWST testc
    T1="$1"
    C1="$2"
    i=0
    NEWST=""
    if [[ -z "$T1" || -z "$C1" ]]; then
	errormsg "Error: No pattern given ($T1, $C1)"
	return
    fi
    while [[ $i -lt ${#T1} ]]
    do
	testc=${T1:$i:${#C1}}
	if [[ "$testc" != $C1 ]]; then
	   NEWST="${NEWST}$testc"
	fi
	i=$(( $i + ${#C1} ))
    done
    RETVAL="$NEWST"
}
	   
function beprintline()
{
    # for debugging this is a replacement for echo.
    echo "$@"
}

function beinsertat()
{
    # insert $2 at BUFF location $1
    # pass vales are 1 to max
    # but strings are processed as 0 to max-1
    local i Newv    
    i="$1"
    i=$(( $i - 1 ))
    if [[ $i -lt 0 ]]; then
	errormsg "Invalid Index"
	return
    fi
    Newv="$2"
    BUFF=( "${BUFF[@]:0:$i}" "$Newv" "${BUFF[@]:$i}" )
}

function bedeleteat()
{
    # delete line# $1 from Buff
    local j
    j=$(( $1 - 1 ))
    BUFF=( "${BUFF[@]:0:$j}" "${BUFF[@]:$1}" )
}

function befindreplace()
{
    # The handles the function s/pattern/replace/[g]
    # is 'smart' enough to handle simple backslash quoting and an optional 'g' lobal flag.
    # More complicated flags and quote subsution (\1 \2 etc) are NOT supported.
    local INVALUE SUBREP PATTERNS i PATTERNIDX fc backslash GLOBAL OUTVAL
    RETVAL=""
    INVALUE="$1"
    SUBREP="$2"
    PATTERNS=()
    i=0
    backslash=0
    PATTERNIDX=0
    if [[ ${SUBREP:0:1} == "/" ]]; then
	# Skip first slash
	i=$(( $i + 1 ))
    fi
    while [[ $i -lt ${#SUBREP} ]];
    do
	fc=${SUBREP:$i:1}
	if [[ "$fc" = "/" ]]; then
	    if [[ $backslash == 0 ]]; then
		PATTERNIDX=$(( $PATTERNIDX + 1 ))
	    fi
	    fc=""
	fi
	if [[ "$fc" = "\\" && $backslash = 0 ]]; then
	    backslash=1
	else
	    PATTERNS[$PATTERNIDX]+=$fc	    
	fi
	i=$(( $i + 1 ))
    done
    GLOBAL=0
    if [[ ${#PATTERNS[@]} -lt 1 ]]; then
	errormsg "Invalid search/replace option"
	RETVAL=$INVALUE
	return
    fi
    if [[ ${#PATTERNS[@]} -gt 2 ]]; then
	if [[ $PPATTERNS[2] == "g" ]]; then
	    GLOBAL=1
	fi
    fi
    if [[ $GLOBAL == 0 ]]; then
	OUTVAL=${INVALUE/"${PATTERNS[0]}"/"${PATTERNS[1]}"}
    elif [[ $GLOBAL == 1 ]]; then
	OUTVAL=${INVALUE//"${PATTERNS[0]}"/"${PATTERNS[1]}"}
    fi
    RETVAL="$OUTVAL"
}



function loadbuffer()
{
    BUFF=()
    MODIFIED=false
    if [[ -e $1  ]]; then
	if [[ "$1" != "--un-named--" ]]; then
	    set -f
	    while read line; do
		BUFF+=("${line}")
	    done < $1
	    set +f
	fi
    fi
}

function parseinline()
{
    # Pass as agument a string
    # Will be split into colon seperated list, parsed by pattern
    #  /string/opt-string/[cmd][rest] returns cmd:range:-1:-1:rest
    #  [0-9]*(-[0-9]*)[cmd][rest] return cmd::N:M:rest
    #  cmd[rest] returns cmd::-1:-1:rest
    #  Primary function is to parse command lines
    #  But as the search and replace commands take string arguments that are
    #  nearly idential to the cmd pattern, it can do double duty to parse 'rest'
    #  with a second pass.
    local tmp1 cmd range anumber bnumber params i fc
    tmp1="$1"
    cmd="search"
    range=""
    anumber=""
    bnumber=""
    params=""
    i=0
    if [[ ! -z "$tmp1" ]]; then	
	fc=${tmp1:0:1}	
	if [[ "$fc" = "/" ]]; then
	    # We support a simple backslash quoteing syntax
	    # Its not fully featured and does not provide support for ocatal
	    # other common specaial character quoting (like no \n for nl)
	    backslash=0
	    i=0
	    parmcnt=0
	    while [[ $i -lt ${#tmp1} && $parmcnt -lt 2 ]]
	    do
		if [[ ${tmp1:$i:1} == / ]]; then
		    if [[ $backslash == 0 ]]; then
			parmcnt=$(( $parmcnt + 1 ))
		    fi
		fi
		if [[ ${tmp1:$i:1} == '\\' ]]; then
		    backslash=1
		else
		    backslash=0
	        fi
		i=$(( $i + 1 ))
	    done
	    range=${tmp1:0:$i}
	    fc=${tmp1:i:1}
	elif [[ ( ! $fc < '0' && ! $fc > '9' ) || $fc == '$' || $fc == '.' || $fc == '+' || $fc == '-' ]]; then
	    # Our rule is anumber gets filled first. With bnumber
	    # being optional.
	    i=0
	    finish=0
	    anumber=
	    bnumber=
	    RELATIVE=0
	    while [[ $i -lt ${#tmp1} && $finish -lt 2 ]]
	    do
		tc=${tmp1:$i:1}
		if [[ $tc == '$' ]]; then
		    if [[ $finish == 0 ]]; then
			anumber=${#BUFF[@]}
		    fi
		    if [[ $finish == 1 ]]; then
			bnumber=${#BUFF[@]}
		    fi
		elif [[ $tc == '.' ]]; then
		    if [[ $finish == 0 ]]; then
			anumber=$CURLIN
		    fi
		    if [[ $finish == 1 ]]; then
			bnumber=$CURLIN
		    fi		    
		elif [[ ! $tc < '0' && ! $tc > '9'  ]]; then
		    if [[ $finish == 0 ]]; then
			anumber=$anumber$tc
		    fi
		    if [[ $finish == 1 ]]; then
			bnumber=$bnumber$tc
		    fi
		elif [[ $tc == '-' ]]; then
		    RELATIVE="$RELATIVE-"
		elif [[ $tc == '+' ]]; then
		    RELATIVE="$RELATIVE+"
		else
		    finish=$(( $finish + 1 ))
		fi
		i=$(( $i + 1 ))
	    done
	    # Logic for handeling relative line number
	    if [[ $RELATIVE != 0 ]]; then

		RELATIVE="$RELATIVE  "
		if [[ "X${RELATIVE:1:1}" == 'X+' ]]; then
		    [[ -z "$anumber" ]] && anumber=1
		    anumber=$(( $CURLIN + $anumber ))
		fi
		if [[ "X${RELATIVE:1:1}" == 'X-' ]]; then
		    [[ -z "$anumber" ]] && anumber=1		    
		    anumber=$(( $CURLIN - $anumber ))		    
		fi
		if [[ "X${RELATIVE:2:1}" == 'X+' ]]; then
		    [[ -z "$bnumber" ]] && bnumber=1		    
		    bnumber=$(( $CURLIN + $bnumber ))
		fi
		if [[ "X${RELATIVE:2:1}" == 'X-' ]]; then
		    [[ -z "$bnumber" ]] && bnumber=1
		    bnumber=$(( $CURLIN - $bnumber ))
		fi		
	    fi
	    i=$(( $i - 1 ))
	    fc=${tmp1:i:1}	    	    
	fi
	if [[ ! $fc < 'a' && ! $fc > 'Z'  ]]; then
	    # Drop here and return the single character of the cmd
	    cmd=$fc
	fi
	if [[ $fc == '=' ]]; then
	    i=$(( $i - 1 ))
	fi
    fi
    i=$(( $i + 1 ))
    RETVAL="$cmd:$range:$anumber:$bnumber:${tmp1:$i:1000}"
}

function besearch()
{
    bermchar "$1" "/"
    T1="$RETVAL"
    
    if [ ! -z "$T1" ]; then
	# We passed a new pattern in, remove '/'s and set it to SEARCHPAT
	SEARCHPAT="$T1"
    else
	# No new pattern, use previous SEARCHPAT if any was set.
	if [ -z "$SEARCHPAT" ]; then
	    errormsg "Error, no search pattern given."
	    SEARCHPAT="."
	fi	
    fi
    i=$(( $CURLIN  ))
    MATCH=0
    while [[ $i -lt ${#BUFF[@]} ]];
    do
	TESTLN="${BUFF[$i]}"
	if [[ $TESTLN =~ $SEARCHPAT ]]; then
#	    CURLIN=$(( $i + 1 ))
	    MATCH=$(( $i + 1 ))
	    break
	fi
	i=$(( $i + 1 ))
    done
    if [ "$MATCH" == "0" ]; then
	errormsg "No Match for $SEARCHPAT. Restart at top of file"
	RETVAL=1
    else
	RETVAL="$MATCH"
    fi
}
	     


function bevalidrange()
{
    if [[ -z "$1" && -z "$2" ]]; then
	beprintline "Error in range: $CURLIN"
    else
	if [[ "X$2" != "X" && "X$1" == "X" ]]; then
	    # In cases where two parameters are passed but the first
	    # paramter is empty "" then use the second.
	    # This is for cases were user entered only one number
	    # so the 'range' is anumber to anumber with no bnumber
	    shift
	fi
	case "$1" in
	    ''|*[!0-9-]*)
		errormsg "Error, $1 not a number: $CURLIN"
		;;
	    *)
		if [ "$1" -gt ${#BUFF[@]} ]; then
		    beprintline "${#BUFF[@]}"
		elif [ "$1" -lt 0 ]; then
		    beprintline "0"
		else
		    beprintline "$1"
		fi
		;;
	esac
    fi   
}


function bed()
{
    
    while getopts "hd" FLAG; do
	case $FLAG in
	    h)
		errormsg "Usage:"
		errormsg "$0 filename"
		;;
	    d)
		N=$(date +%s%N)
		export PS4='+[${SECONDS}s][${BASH_SOURCE}:${LINENO}]: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'; set -x;
		#	    export PS4='+[$(((`date +%s%N`-$N)/1000000))ms][${BASH_SOURCE}:${LINENO}]: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
		set -xv	    
		#	    export PS4='$LINENO: '
		#	    set -x
		DEBUGMODE=on
		;;
	esac
    done

    shift $((OPTIND-1))

    for fn in $@
    do
	BUFFERFN+=($fn)
    done


    if [[ ${#BUFFERFN[@]} == 0 ]]; then
	BUFFERFN[0]="--un-named--"
    fi

    MODE="CMD"
    MODEPROMPT=">"
    PRELOAD=""
    beprintline "Load: ${BUFFERFN[$BUFFID]}"
    loadbuffer ${BUFFERFN[$BUFFID]}
    QUITPAT='^q'
    while [[ $MODE != "QUIT" ]];
    do    
	IFS=  read -p "$CURLIN $MODEPROMPT" -e INPT

	if [[ $MODE == "CMD" ]]; then
	    if [[ $INPT =~ $QUITPAT ]]; then
		set -xv
		if [[ "$MODIFIED" == "false" ]]; then
		    MODE="QUIT"
		else
		    if [[ "$INPT" == "q!" ]]; then
			MODE="QUIT"
		    else
			beprintline "? Modification not saved. Use q! to quit"
		    fi
		fi
		INPT=""
	    elif [[ ! $INPT =~ $QUITPAT ]]; then
		#	    OUTP=$( parseinline "$INPT" )
		parseinline "$INPT"
		OUTP="$RETVAL"
		OLDLINE=$CURLIN
		#	    parseinline "$INPT"
		IFS=":" read -r -n 999 cmd range anumber bnumber rest <<< $(echo $OUTP)
		while [[ ${rest:0:1} == " " ]]
		do
		    rest=${rest:1}
		done
		if [ -z "$anumber" ]; then
		    anumber=$CURLIN
		fi
		if [ -z "$bnumber" ]; then
		    bnumber="$anumber"
		fi
		anumber=$( bevalidrange "$anumber")
		bnumber=$( bevalidrange "$bnumber" "$anumber")
		CURLIN="$bnumber"	
		if [ ! -z "$range" ]; then
		    # A 'range' was given. This is basicly a search to find first
		    # line with that match.
		    besearch "$range"
		    NEWCUR="$RETVAL"
		    if [ $NEWCUR != -1 ]; then
			TEST__CURLIN="$NEWCUR"
			CURLIN=$NEWCUR
		    fi
		    anumber=$CURLIN
		    bnumber=$CURLIN
		fi
		case $cmd in
		    search)
			if [ ! -z "$rest" ]; then
			    if [ "$rest" == "=" ]; then
				beprintline $CURLIN
			    fi
			else
			    j=$( bevalidrange $(( $CURLIN - 1 )) )
			    beprintline "${BUFF[$j]}"
			fi
			;;
		    a)
			MODE="INPUT"
			MODEPROMPT="Append*"
			if [[ ${#BUFF[@]} -lt $CURLIN ]]; then
			    CURLIN=$(( $CURLIN + 1 ))
			fi
			beprintline "Enter '.' on empty line to return to cmd mode:"
			while [[ "$MODE" == "INPUT" ]];
			do
			    NUMPRMT=$(( $CURLIN - 1 ))
			    IFS= read -p "$MODEPROMPT $NUMPRMT: " -e EINPUT
			    if [[ "$EINPUT" == "." ]]; then
				MODE="CMD"
				MODEPROMPT=">"
			    else
				beinsertat $CURLIN "$EINPUT"
				CURLIN=$(( $CURLIN + 1 ))
			    fi
			done
			MODIFIED=true
			;;
		    c)
			MODE="CHANGE"
			MODEPROMPT="Change%"
			if [[ ! -z "$rest" ]]; then
			    BUFF[$CURLIN]="$rest"
			    CURLIN=$(( $CURLIN + 1 ))
			fi
			beprintline "Enter '.' on empty line to return to cmd mode:"
			while [[ "$MODE" == "CHANGE" ]];
			do
			    NUMPRMT=$(( $CURLIN ))
			    IFS= read -p "$MODEPROMPT $NUMPRMT:" -e EINPUT
			    if [[ "$EINPUT" == "." ]]; then
				MODE="CMD"
				MODEPROMPT=">"
			    else
				BUFF[$CURLIN]="$EINPUT"
				CURLIN=$(( $CURLIN + 1 ))
			    fi
			done
			MODIFIED=true			
			;;
		    d)
			for i in $( seq $anumber $bnumber )
			do
			    bedeleteat $(( $anumber + 1 ))
			done
			;;
		    e)
			if [[ ${rest:0:1} == "<" ]]; then
			    # Case for shell functions
			    BUFF+=( $( ${rest:1} ) )
			else
			    if [ -f ${rest} ]; then
				loadbuffer ${rest}
				BUFFERFN[0]="${rest}"
				MODIFIED=true			
			    else
				errormsg "File: $rest, not found"
			    fi
			fi
			;;
		    
		    i)
			MODE="INPUT"
			MODEPROMPT="Insert*"
			beprintline "Enter '.' on empty line to return to cmd mode:"
			CURLIN=$(( $CURLIN + 1 ))
			while [[ "$MODE" == "INPUT" ]];
			do
			    NUMPRMT=$(( $CURLIN - 1 ))
			    IFS= read -p "$MODEPROMPT $NUMPRMT:" -e EINPUT
			    if [[ "$EINPUT" == "." ]]; then
				MODE="CMD"
				MODEPROMPT=">"
			    else
				beinsertat $CURLIN "$EINPUT"
				CURLIN=$(( $CURLIN + 1 ))
			    fi
			done
			MODIFIED=true
			;;
		    m)
			if [[ -z "$rest" || "X$rest" == "X." ]]; then
			    dest=$CURLIN
			else
			    if [[ ${rest:0:1} > "9" || ${rest:0:1} < "0" ]]; then
				# The lack of <= for strings means odd reverse logic
				# we get here if its NOT a number
				besearch "$rest"
				dest="$RETVAL"
				if [ $dest == -1 ]; then
				    errormsg "No match for destination"
				    dest=$CURLIN
				fi
			    else
				dest=$( bevalidrange "$rest")
			    fi
			fi
			movesize=$(( $bnumber - $anumber + 1 ))
			CBUFF=()
			anumber=$(( $anumber - 1 ))
			bnumber=$(( $bnumber - 1 ))
			      
			for i in $(seq $anumber $bnumber)
			do
			    echo "${BUFF[$i]}" > /dev/null
			    CBUFF+=( "${BUFF[$i]}" )
			done
			for i in $(seq 1 $movesize)
			do
			    bedeleteat $(( $anumber + 1 ))
			done		    
			if [[ $dest -gt $anumber ]]; then
			    dest=$(( $dest - $movesize + 1 ))
			fi
			i=$dest
			for line in "${CBUFF[@]}"
			do
			    beinsertat $i "$line"
			    i=$(( $i + 1 ))
			done
			MODIFIED=true
			;;		    
		    n)
			CURLIN=$OLDLINE
			beprintline "---- $anumber - $bnumber --- ( $CURLIN )"
			for i in $(seq $anumber $bnumber)
			do
			    j=$(( $i - 1 ))
			    if [[ $i == $CURLIN ]]; then
				printf "*"
			    fi
			    beprintline $i": ${BUFF[$j]}"
			done
			;;
		    p)
			CURLIN=$OLDLINE
			beprintline "---- $anumber - $bnumber --- ( $CURLIN )"		    
			for i in $(seq $anumber $bnumber)
			do
			    j=$(( $i - 1 ))
			    if [[ $i -eq $CURLIN ]]; then
				printf "*"
			    fi			
			    if [ "X$rest" == "X=" ]; then
				beprintline $i": ${BUFF[$j]}"
			    else
				beprintline "${BUFF[$j]}"
			    fi
			done
			;;
		    s)
			if [ -z "$rest" ]; then
			    errormsg "No Pattern given."
			else
			    for i in $(seq $anumber $bnumber)
			    do
				if [ $i -le ${#BUFF[@]} ]; then
				    befindreplace "${BUFF[$i]}" "$rest"
				    BUFF[${i}]="$RETVAL"
				fi
			    done
			fi
			;;
		    t)
			if [[ -z "$rest" || "X$rest" == "X." ]]; then
			    dest=$CURLIN
			else
			    if [[ ${rest:0:1} > "9" || ${rest:0:1} < "0" ]]; then
				# The lack of <= for strings means odd reverse logic
				# we get here if its NOT a number
				besearch "$rest"
				dest="$RETVAL"
				if [ $dest == -1 ]; then
				    errormsg "No match for destination"
				    dest=$CURLIN
				fi
			    else
				dest=$( bevalidrange "$rest")
			    fi
			fi
			movesize=$(( $bnumber - $anumber + 1 ))
			CBUFF=()
			anumber=$(( $anumber - 1 ))
			bnumber=$(( $bnumber - 1 ))
			
			for i in $(seq $anumber $bnumber)
			do
			    echo "${BUFF[$i]}" > /dev/null
			    CBUFF+=( "${BUFF[$i]}" )
			done
			i=$(( dest + 1 ))
			for line in "${CBUFF[@]}"
			do
			    beinsertat $i "$line"
			    i=$(( $i + 1 ))
			done
			MODIFIED=true
			;;
		    w)
			if [[ $rest == "" ]]; then
			    if [[ "${BUFFERFN[0]}" == "--un-named--" ]]; then
				beprintline "Buffer does not have a filename. Use w filename."
			    else
				if [[ -w "${BUFFERFN[0]}" ]]; then
				    cp /dev/null ${BUFFERFN[0]}
				    for i in $(seq 0 $(( ${#BUFF[@]} - 1 )) )
				    do
					printf "%s\n" "${BUFF[$i]}" >> ${BUFFERFN[0]}
				    done
				    cat ${BUFFERFN[0]} | wc
				    MODIFIED=false
				else
				    beprintline "Given File (${BUFFERFN[0]}) is not writable, use w! to attempt to override"
				fi
			    fi
			else
			    MODIFIED=false
			    OLDPERM=$(stat -c%a ${BUFFERFN[0]})

			    if [[ "$rest" == "!" ]]; then
				if [[ ! -w "${BUFFERFN[0]}" ]]; then
				    chmod u+w ${BUFFERFN[0]} || beprintline "Error trying to write to ${BUFFERFN[0]}"
				fi
			    else
				BUFFERFN[0]="$rest"
			    fi
			    cp /dev/null ${BUFFERFN[0]}
			    for i in $(seq 0 ${#BUFF[@]})
			    do
				printf "%s\n" "${BUFF[$i]}" >> ${BUFFERFN[0]}
			    done
			    cat ${BUFFERFN[0]} | wc			    
			    if [[ "$rest" == "!" ]]; then
				# if we were forcing the write, return file to original permisisons.
				chmod $OLDPERM ${BUFFERFN[0]}
			    fi
			fi
			;;
		
		    .)
			beprintline $CURLIN
			;;
		    X)
			CURLIN=$OLDLIN		    
			if [[ $DEBUGMODE == "on" ]]; then
			    set +xv
			    DEBUGMODE=off
			    errormsg "Debug Mode $DEBUGMODE"
			else
			    set -xv
			    DEBUGMODE=on
			    export PS4='$LINENO: '
			    errormsg "Debug Mode $DEBUGMODE"
			fi
			;;
		    h) cat <<EOF
bedit help: 
This is a 'pure' bash shell script editor.
In general the syntax should be close to classic ed but it does
not try to re-create all ed functions or commands.
    Core commands:
    [range|/pattern]CMD[Options]
	range is number[-number] 
	pattern is /pattern/  (at this time there is no way to quote '/')
    CMD is one of the set (a, d, e, i, p , s ,  w , q  , X)
        a == Enter 'Input' mode starting with next line.
	c == Change/overwright mode starting at current line.
	d == delete range
	e[filename] == edit a new file, or if no filename given
		    abandon all changes and reload current file.
	i == Enter 'Input' mode start with line above currnet line.
	m == src-range m dst. Moves lines from src range to dst.
    	p == Print lines in range
	     option '=' pre-pends the line number
	s/P1/P2/[g] == Substitue on current line/range of lines,
		       Pattern P1 with P2
		       Some bash flavor RegExs will work but dont try
		       to get too fancy.
	t == src-range t dst, Copies lines from src range to dst.
	     Very similure to 'm'ove but does not delete original src lines.
	w[filename] == write current buffer to either default file or new file
		    if new file is given then it will be come the new default
		    filename. If no default filename exists (bedit started
		    without a filename) then it will error if you fail to
		    give a filename.
		    use 'w!' to override a read only file
		    ...ONLY if you have permisssion to 'chmod' that file.
	q == quit. use q! if file has been modified.
	X == Toggle 'debug' output.
EOF
		       ;;
		    *)
			errormsg "Not yet implimented"
			;;		
		esac
	    fi
	fi
    done
}

# Main function call

bed $*
