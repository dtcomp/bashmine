#!/bin/bash
LC_ALL=C
set -u
set -i

source ./bm-util.sh

## Constants
declare -rig RowsMin=3
declare -rig RowsMax=26
declare -rig ColsMin=3
declare -rig CellsMin=$(( $RowsMin * $ColsMin ))
declare -rig CellsMax=$(( 26*26 ));
declare -rg  RPath=$( realpath $( dirname $0 ) )
declare -rAg Term=( [bld]=$(tput bold) \
					[sto]=$(tput smso) \
					[sti]=$(tput rmso) \
					[rst]=$(tput sgr0) \
					[nom]=$(tput rmso) \
					[rev]=$(tput rev) \
					[fred]=$(tput setaf 1) \
					[fgrn]=$(tput setaf 2) \
					[fwht]=$(tput setaf 7) \
					[bred]=$(tput setab 1) \
					[bgrn]=$(tput setab 2) \
					[bwht]=$(tput setab 7) \
					[fdef]=$(tput setaf 9) \
					[bdef]=$(tput setab 9) \
					[def]="${Term[fdef]}${Term[bdef]}"
					 );

## Globals
declare -g   HelpFile=README.md
declare -g   MapPath=${RPath}/maps
declare -ag  HelpText

## Option Defaults
declare Mode=Normal
declare -i Width=9
declare -i Height=9
declare -i PromptLevel=3
declare -i DensityDivisor=5
declare -i MineCount=0



## Help Info
help(){
  local lines=$(( $( tput lines ) - 1 ))
  local file="${RPath}/${HelpFile}"
  [ -e $file ] && [ -f $file ] && [ -r $file ] || echo "Can't read $file!" ;
  exec 4<$file
  readarray -n0 -u4 HelpText;
  set -f
  inter "$lines" 'HelpText' "${#HelpText[@]}";
  set +f
}


options(){
  local size;
  local opt;

  while getopts c:d:p:s:rh opt $*; do

	case $opt in
	c)
	  MineCount=$(( $OPTARG + 0 ));
	  DensityDivisor=0;
	  ;;
	d)
	  DensityDivisor=$(( $OPTARG + 0 ));
	  [ $DensityDivisor -lt 2 ] && echo "Density Divisor too small: $DensityDivisor" && exit 1;
	  ;;
	p)
	  PromptLevel=$(( $OPTARG + 0 ))
	  ;;
	s)
	  size=$OPTARG;
	  Height=$(( ${size%%x*} + 0 ))   #Rows
	  Width=$(( ${size##*x} + 0 ))    #Cols
	  ;;
	r)
		Mode=Reveal;
	  ;;
	h)
	  help;
	  ;;
	*)
	  help;
	esac;
  done

  if [ $Height -gt $RowsMax -o $Height -lt $RowsMin ]; then
    echo "OOPS, Rows must be in range: $RowsMin..$RowsMax"
    exit 1; 
  fi
  if [ $Width -lt $ColsMin ]; then
    echo "OOPS, Minimum columns is: $ColsMin"
    exit 1; 
  fi
}


validAddr(){
  local row=$( ord $1 );
  local col=$2;

  [  $row -ge $RowStartOrd ] && [ $row -le $RowEndOrd ] && [ $col -ge $ColStart ] && [ $col -le $ColEnd ] 
}


# Just verify the argument represents a valid cell attribute name.
isCellAttr(){
  [ $# -eq 0 ] || [ $# -gt 1 ] && return 1;
  local rc=0;
  local oifs=$IFS;    # prep to turn CellAttr keys into alternates regexp
  IFS=\|
  [[ "$1" =~ ${!CellAttr[*]} ]] || rc=1;
  IFS=$oifs;
  return $rc;
}


## for debugging
dumpMap(){
  local a k;
  for a in $Range; do
    echo -n "$a=( "
    for k in "${!CellAttr[@]}"; do
      echo -n "[${k}]="$(cell.get $a $k)" ";
    done
      echo " );";
  done
}


dumpMapFile(){
	dumpMap > "${MapPath}/Mapfile-${Rows}x${Cols}";
}


initGeom(){
  local width=$1;
  local height=$2;

## Geometry Constants
  declare -rig Rows=$height
  declare -rig Cols=$width
  declare -rig Cells=$(($Rows*$Cols))
  if [ $DensityDivisor -ne 0 ]; then
    MineCount=$(($Cells/$DensityDivisor));
  fi
## Map Constants
  declare -rg  RowStart=A
  declare -rig RowStartOrd=$(ord $RowStart);
  declare -rg  RowEnd=$(  chr $(( $RowStartOrd + $height -1 )) )
  declare -rig RowEndOrd=$(ord $RowEnd);
  declare -rig ColStart=1
  declare -rig ColEnd=$Cols

  declare -rag RowRange=( $( eval echo {"$RowStart..$RowEnd"} ) );
  declare -rag ColRange=( $( eval echo {"$ColStart..$ColEnd"} ) )
  declare -rg  Range=$(eval echo "{${RowStart}..${RowEnd}}{${ColStart}..${ColEnd}}")
  declare -rag RowNames=( $(eval echo "${RowRange[@]}") );
  declare -rag ColNames=( $(eval echo "${ColRange[@]}") );
  declare -rg  BottomRow=$( chr $(( $Rows + 65 )) )

## Map Vars
  declare -Ag  Visited=();
  declare -Ag  Neighbors;
}


initCell() {
  ## CellState Enum
  declare -rag CellState=( [0]=Initial [1]=Cleared [2]=Marked [4]=Detonated );
  for x in ${!CellState[@]}; do
    eval 'declare -rng '${CellState[$x]}'=CellState['$x'];';
  done
  ## CellType Enum
  declare -rag CellType=([0]=Clear [1]=Bomb);
  for x in ${!CellType[@]}; do
    eval 'declare  -rng '${CellType[$x]}'=CellType['$x'];';
  done
  ## Cell Attributes ( with Default values )
  declare -rAg CellAttr=( [Type]=$Clear [State]=$Initial [MineNeighbors]=0 )
}


# Reinitializes a previously declared map,
# setting values to predetermined default
initCellMap(){
  local a;

  for a in $Range; do
    eval $a"=( [Type]=$Clear [State]=$Initial [MineNeighbors]=0 );"
    Visited[$a]=0;
  done
}

declareCellMap(){
  local rRange=$1;
  local cRange=$2;
  local row col;

  for row in $rRange; do
    for col in $cRange; do
	  ## declare a Cell
      declare -Ag $row$col;
    done;
  done
}


initNav(){
  local x;
  
  #declare -A Dir=( [X]=0 [Y]=0 [North]=-1 [South]=+1 [East]=+1 [West]=-1  )
  declare -rAg Dir=( [X]=echo [Y]=echo [North]=pred [South]=succ [East]=inc [West]=dec  );
  for x in ${!Dir[@]}; do
    eval "declare -rng "$x"=Dir["$x"];";
  done

  declare -rAg Heading=( [NW]= [N]= [NE]= [E]= [SE]= [S]= [SW]= [W]= );
  declare -rAg NW=( [row]=$North [col]=$West );
  declare -rAg  N=( [row]=$North [col]=$Y );
  declare -rAg NE=( [row]=$North [col]=$East );
  declare -rAg  E=( [row]=$X     [col]=$East );
  declare -rAg SE=( [row]=$South [col]=$East );
  declare -rAg  S=( [row]=$South [col]=$Y );
  declare -rAg SW=( [row]=$South [col]=$West );
  declare -rAg  W=( [row]=$X     [col]=$West );

  # generate Navigationals
  for x in ${!Heading[@]}; do
    eval $x".from(){
    local from_row=\$1;
    local from_col=\$2;
    to_row=\$(\${"$x"[row]} \$from_row);
    to_col=\$(\${"$x"[col]} \$from_col);
    echo \$to_row \$to_col; };";
  done
}


# Calculate Neighbors of a given cell
getNeighbors(){
  local n row col c=$1;
  declare -a tmp=();
  declare -a a;
  declare -i i=0;

  x=${Neighbors[$c]-no};
  if [ $x = no ]; then
  	  row=${c%%[${ColRange[@]}]*};
  	  col=${c##[${RowRange[@]}]};
	  for n in "${!Heading[@]}"; do
        a=( $( ${n}.from $row $col ));
        if validAddr ${a[0]]} ${a[1]}; then
          tmp[$i]="${a[0]}${a[1]}";
          (( i++ ))
        fi
      done;
      Neighbors[${c}]="${tmp[@]}";
      echo ${tmp[@]};
  else
    echo ${Neighbors[$a]};
  fi
}

# Create static map of Cells neighbor relations
# This takes a long time for larger grids.
# The above approach spreads some of the time out...
# So, not used.
initNeighbors(){
  local row col c i n;
  declare -a a;
  declare -a tmp;
  
  for row in ${RowRange[@]}; do
    for col in ${ColRange[@]}; do
      c="$row$col";
      i=0;
      tmp=();
	  for n in "${!Heading[@]}"; do
        a=( $( ${n}.from $row $col ));
        if validAddr ${a[0]]} ${a[1]}; then
          tmp[$i]="${a[0]}${a[1]}";
          (( i++ ))
        fi
      done;
      Neighbors[${c}]="${tmp[@]}";
      Visited[${c}]=0;
    done
  done
}


initPlay(){
  ## Play Variables
  declare -ig Turns=0
  declare -ig Errors=0
  declare -ig Digs=0
  declare -ig Marks=0
  declare -ig UnMarks=0
  declare -ig MisMarks=0
  declare -ig Remaining=$(( Cells-MineCount ));
  declare -Ag Time=( [Start]=$(date '+%s') [Elapsed]=0 );
}


## $1 = cell address
## $2.. Specific keys to get, otherwise get all keys
cell.get(){
  local rc=0;

  case $# in
  0)
    echo "$FUNCNAME[0]: Error: no Cell specified..";
    rc=1;
    ;;
  1)
   echo $(eval echo "\${"${1}"[@]};" );
   ;;
  2)
   echo $(eval echo "\${"${1}"[${2}]};" );
  ;;
  3..9)
   local k;
   shift 2;
   for k in $*; do
     echo $(eval echo "\${"${1}"[$k]}; " );     
   done
   ;;
   *)
     rc=-1;
   ;;
   esac;
   
  return $rc;
}

## $1 = cell address
## $2.. Specific keys to set, otherwise set all key/value pairs
cell.set(){
  local rc=1;
  case $# in
  0)
    echo "$FUNCNAME[0]: Error: no Cell specified..";
    ;;
  1)
    echo "$FUNCNAME[0]: Error: no Key specified..";
    ;;
  2)
    echo "$FUNCNAME[0]: Error: no Value specified..";
    ;;
  3)
    eval "${1}[${2}]=${3}";
    rc=0;
    ;;
  4)
    echo "$FUNCNAME[0]: Error: Invalid # or parameters..";
    ;;
  5|7|9|11)
   local c=$1;
   shift 1;
   until [ $# -eq 0 ]; do
     eval "${c}[${1}]=${2};";
     shift 2;
   done
   rc=0;
   ;;
   *)
   rc=-1;
   ;;
   esac;   
  return $rc;
}

## $1=target_cell
## Increment Mine neighbors count for cell
cell.inc(){
  local rc=0;
  case $# in
  0)
    echo "$FUNCNAME: Error: no Cell specified..";
    rc=1;
    ;;
  1)
    eval "(( ${1}[MineNeighbors]++ ));";
    ;;
  *)
    rc=-1;
   ;;
   esac;
 
  return $rc;
}


# Elapsed time
et(){
  local now=$(date +%s)
  local elapsed=$(( $now-${Time[Start]} )); # seconds..
  printf '%02d:%02d' $(( $elapsed/60 )) $(( $elapsed%60 ));
}

# Status line
# $1=cols
status(){
 local cols=$1
 local ll=$(( ( cols * 2 ) + 5 ));
 local l=$(printf "%.${ll}s" '---------------------------------------------------------' );
 local t=$(et);
 local d=$(printf '%03d' $Digs)
 local r=$(printf '%03d' $Remaining)
 local m=$(printf '%03d' $((MineCount-Marks)))
 local spacer=$(( (( cols - 3 ) * 2 ) + 1 ))
 local s=$(printf "%${spacer}s" ' ')
 echo ' '$l;
 echo " D:${d}${s}?:${r}"
 echo " ${t}${s}M:${m}"
 return;
}


## Print Map Header
header(){
  local cols=$1;
  local i=0

  echo -n ' -+'
  i=0;
  while [ $i -lt $cols ]; do
    echo -n '--'; ((i++));
  done
  echo '-+-'

  i=0;
  if [ $cols -gt 9 ]; then 
    echo -n '  |';
    while [ $i -lt $cols ]; do
      if [ $i -ge 9 ]; then
        echo -n " $(( (($i+1)/10) ))";
      else
        echo -n '  ';
      fi
      (( i++ ))
    done
    echo ' |'
  fi
  echo -n '  |';  
  i=0;
  while [ $i -lt $cols ]; do
    echo -n " $(( ($i+1)%10 ))"; ((i++));
  done
  echo ' |';
  echo -n ' -+-';
  i=0;
  while [ $i -lt $cols ]; do
    echo -n '--'; ((i++));
  done
  echo '+'
}

footer(){
  local cols=$1;
  local i=0;
  echo -n ' -+'
  while [ $i -lt $cols ]; do
    echo -n '--'; ((i++));
  done
  echo '-+'  
}


## Place Mines
## $1 = Number of mines
## $2 = Map Rows
## $3 = Map Columns
## $4 = Single Cell address to "protect" (including neighbors)
layMines() {
  local mines=$1;
  local rows=$2;
  local cols=$3;
  local m ma n c a t o;
  declare -a omit=( $4 );
  
  o=1;
  for t in $( getNeighbors $4 ); do
    omit[$o]=$t;
    (( o++ ))
  done

  # echo "Omitting: ${omit[@]}";

  (( cols-- ))  # since it's 1-based
  m=0;
  while [ $m -lt $mines ]; do
    r=$(( $RANDOM % $rows ));
    c=$(( $RANDOM % $cols ));
    (( c++ ))
    ma=$( chr $(( $r+65 )) )$c;
    for t in "${omit[@]}"; do
      if [ $t = $ma ]; then
        continue 2;
      fi
    done
    omit[$o]="$ma";
    (( o++ ))
    cell.set $ma Type $Bomb;
    for n in $( getNeighbors $ma ); do
      [ $( cell.get ${n} Type) = $Clear ] && cell.inc ${n};
    done
    (( m++ ))
  done
}


## $1=Render Mode
renderMap(){
  local mode=$1;
  local a t s;
  local a row col;
  
  for row in ${RowRange[@]}; do
    echo -n " $row|"
    for col in ${ColRange[@]}; do
      a="$row$col";
      t=$( cell.get $a Type );
      s=$( cell.get $a State );

	  if [ $mode = Normal ]; then
        case $s in
          $Initial)
            echo -n ' .'; continue;
        	;;
          $Cleared)
            echo -n ' '$( cell.get $a MineNeighbors ); continue;
            ;;
          $Marked)
            echo -n ' M'; continue;
            ;;
          $Detonated)
            echo -n ' @'; continue;
            ;;
          *)
           echo -n ' ?'; continue;
        esac;
      fi
      if [ $mode = Reveal ]; then
        case $t in
        $Bomb)
          case $s in
          $Initial)
            echo -en " ${Term[fred]}@${Term[def]}"; continue;
            ;;
          $Marked)
          	echo -en " ${Term[fred]}M${Term[def]}"; continue;
          	;;
          $Detonated)
            echo -en " ${Term[fred]}${Term[bwht]}@${Term[def]}"; continue;
            ;;
            *)
            echo -n '??'; continue;
          esac;
          ;;
        $Clear)
          case $s in
          $Initial)
            echo -n ' .'; continue;
          ;;
          $Cleared)
            echo -n '  '; continue;
          ;;
          $Marked)
            echo -en " ${Term[sto]}W${Term[sti]}"; continue;
          ;;
          *)
          echo -n '??'; continue;
          esac;
          ;;
        esac;
      fi
    done
    echo ' |';
  done
}


expand(){
  local origin=$1
  shift;
  local neighbors=$*;
  local n t s;
  
  if [ ${Visited[$origin]} -gt 0 ]; then
    return 1;
  else
    Visited[$origin]=1;
  fi

  for n in $neighbors; do
    if [ $n = $origin ]; then
      return;
    fi

    t=$( cell.get $addr Type );
    if [ $t = $Bomb ]; then
      continue;
    fi

    if [ $(cell.get $n MineNeighbors) -eq 0 ]; then 
      s=$( cell.get $n State );
      if [ $s = $Initial ]; then
#        echo Clearing $n;
        cell.set $n State $Cleared;
        (( Remaining-- ))
      fi

      local -A subNeighbors=();
      local found;
      for n1 in $( getNeighbors $n ); do
        found=0;
        for n2 in $origin $neighbors; do
		  if [ $n1 = $n2 ]; then
			found=1;
		  fi
        done
        if [ $found -eq 0 ]; then
			subNeighbors[$n1]=1;
	    fi
      done
      expand $n ${!subNeighbors[@]};
      Visited[$n]=1;
    fi
  done

}


dig(){
  local addr=$1;
  local t=$( cell.get $addr Type ) ;
  local s=$( cell.get $addr State );

  if [ $s = $Marked ]; then
    return 0;
	echo $addr was previously marked as a mine...
	echo UnMark $addr if you really want to dig here.
	return 0;
  fi

  if [ $t = $Bomb ]; then
    cell.set $addr State $Detonated;
    (( Digs++ ))
    return 1;
  fi

  if [ $s = $Initial ]; then
    #echo Digging $addr;
    cell.set $addr State $Cleared;
    (( Digs++ ))
    (( Remaining-- ))
    if [ $(cell.get $addr MineNeighbors) -eq 0 ]; then
	# echo expand $addr $( getNeighbors $addr );
      expand $addr $( getNeighbors $addr );
    fi
  fi
  
  return 0;
}


mark(){
  local addr=$1;
  local t=$( cell.get $addr Type );
  local s=$(cell.get $addr State);
  local r=1;

  if [ $s = $Cleared ]; then
	echo "Useless mark on $addr, was already cleared!"
  else
  ## "Clear" cell was selected
    if [ $t = $Clear ]; then
      (( MisMarks++ ));
#    	echo Marking $addr;
      cell.set $addr State $Marked;
      r=1;
    else
    ## "Bomb" cell selected
      case $s in
        $Initial)
          (( Marks++ ));
#      	  echo Marking $addr;
          cell.set $addr State $Marked;
          r=0;
          ;;
        $Marked)
          echo "$addr is already marked!"
          ;;
        *)
          echo 'Bad Mark';
      esac;
    fi
  fi
  return $r;
}

unmark(){
  local addr=$1;
  local t=$( cell.get $addr Type );
  local s=$( cell.get $addr State );
  local r=1;

  if [ $t = $Clear ]; then
    if [ $s = $Marked ]; then
      (( MisMarks-- ))
#      echo UnMarking $addr;
      cell.set $addr State $Initial;
    else
      echo $addr in not Marked!
    fi
  else    ## Itsa Bomb cell
    case $s in
      $Initial)
        echo $addr in not Marked!
        ;;
      $Marked)
        (( Marks-- ))
#        echo UnMarking $addr;
        cell.set $addr State $Initial;
        r=0;
        ;;
      *)
      echo 'Bad Unmark';
    esac;
  fi
  return $r;
}


declare -Ag Stati=();

statusCount(){
  local a s t i=1;

  
  Stati[Marks]=0;
  Stati[Cleared]=0;
  Stati[MisMarks]=0;
  Stati[Initial]=0;
  Stati[Detonated]=0;
  
  for a in $Range; do
    s=$(cell.get $a State)
    t=$(cell.get $a Type)
    if [ $t = $Bomb ]; then
    case $s in
      $Marked)
      	(( Stati[Marked]++ ));
      	;;
      $Initial)
      	(( Stati[Initial]++ ));
      	;;
      $Detonated)
      	(( Stati[Detonated]++ ));
      	;;
      	*)
	    echo $(caller) && exit;
      	esac;
    else
	  case $s in
	  $Initial)
	  	(( Stati[Initial]++ ));
	  	;;
	  $Cleared)
	    (( Stati[Cleared]++ ));
	    ;;
	  $Marked)
	    (( Stati[MisMarked]++ ));
	    ;;
	    *)
	    echo $(caller) && exit;
	  esac;
    fi 
    (( i++ ))
  done
  echo
}

showStati(){
	local k;
	
	for k in ${!Stati[@]}; do
	  echo "$k= ${Stati[$k]}.. " $(eval "\$${k};" );
	done
}

BOOM(){
  echo -e "${Term[bld]}BOOM! ${Term[fred]}${Term[bwht]}${Term[sto]}$1${Term[rst]}";
}

MOOB(){
  echo -e "${Term[bld]}HUZZAH! ${Term[sto]}${Term[bgrn]}${Term[fwht]}You found ALL!${Term[rst]}";
}

# Perform one user action, laying mines
# If first "Dig" action.
act(){
  local action=$1;
  local address=$2;
#  	  statusCount;
#  	  showStati;
  
      case $action in
        D|default)
          ## Mines are delayed until 1st choice, so we can eliminate
          ## initial obstacles.
          if [ $Digs -eq 0 ]; then
          	layMines $MineCount $Rows $Cols $address ;
#      		render $Cols Reveal;
      	  fi
          dig $address;
    	;;
    	M)
   		  if [ $Digs -lt 1 ]; then
    	    echo "Not Marking $address."
     	    echo "Dig for at least one mine before Marking.";
     	  else
   		   mark $address;
   		   return 0;
   		 fi
    	;;
    	U)
  	  	  if [ $Digs -lt 1 ]; then
      	  	echo "Dig for at least one mine (and mark something) before UnMarking.";
      	  else
  	  	    unmark $address;
  	  	    return 0;
  	  	  fi
  		;;
    	*)
      	  echo "I\'m confused by action: \"$address -> $action\" ??"
  	  esac;
}


## Parse player-input address expression
## Like: A1-J1, A1-10, A-J1, A1-C3, A1-C, A-C1, A9-J
## Calculate possibly-expanded list of addresses to play
addrParse(){
  local a1 a2 r1 c1 r2 c2;
  local rows="${RowRange[*]}";
  local cols="${ColRange[*]}";

  case $1 in
    [$rows][$cols]*[-][$rows][$cols]*)
    a1=${1%%-*}; a2=${1##*[-]};
    r1=${a1%%[$cols]*}; c1=${a1##*[$rows]};
    r2=${a2%%[$cols]*}; c2=${a2##*[$rows]};
    validAddr $r1 $c1 && validAddr $r2 $c2 || return 1;
    [ $c2 -eq $c1 ] && [ $r1 = $r2 ] && echo $a1 && return;    # if a=b
    if [ $c2 -eq $c1 ]; then
      eval echo "{$r1..$r2}$c1;";
    else
	  eval echo "{$r1..$r2}{$c1..$c2};";
    fi
    ;;
    [$rows][$cols]*[-][$cols]*)
    a1=${1%%-*}; a2=${1##*[-]};
    r1=${a1%%[$cols]*}; c1=${a1##*[$rows]};
	# r2=${a2%%[$cols]*};
    c2=${a2##*[$rows]};
    validAddr $r1 $c1 && validAddr $r1 $c2 || return 1;
    [ $c2 -eq $c1 ] && echo $a1 && return;    # if a=b
    eval echo "$r1{$c1..$c2};";
	;;
    [$rows][-][$rows][$cols]*)
    a1=${1%%[-]*}; a2=${1##*[-]};
    r1=${a1%%[-]*};
    # c1=${a1##*[$rows]};
    r2=${a2%%[$cols]*}; c2=${a2##*[$rows]};
    validAddr $r1 $c2 && validAddr $r2 $c2 || return 1;
    [ $r2 = $r1 ] && echo $a2 && return;    # if a=b
    eval echo "{$r1..$r2}$c2;";
	;;
    [$rows][$cols]*[-][$rows])
    a1=${1%%[-]*}; a2=${1##*[-]};
    r1=${a1%%[$cols]*}; c1=${a1##*[$rows]};
    r2=${a2%%[$cols]*};
    # c2=${a2##*[$rows]};
    validAddr $r1 $c1 && validAddr $r2 $c1 || return 1;
    [ $r2 = $r1 ] && echo $a1 && return;    # if a=b
    eval echo "{$r1..$r2}$c1;";
	;;
	[$rows][$cols])
	  echo $1;
	  ;;
	[$rows][12][$cols])
	  echo $1;
	  ;;
	*)
#	echo Unmatched address expression: $1;
	echo;
	return 1;
  esac;

}

initPrompt(){
	declare -ag Prompt;
	Prompt[1]="One+ cell address expressions, like \"b9\" \"a1-5\" \"a-j5\""
	Prompt[2]="Each optionally followed by one action: \"m\" (mark), \"u\" (unmark), \"d\" (dig)"
	Prompt[3]="dig is the default action if unspecified"
    readonly Prompt;
}

prompt(){
	local l=${1:-${#Prompt[@]}};
    local i;

    for (( i=0; i <= $l; i++ )); do
		[ $i -gt 0 ] && echo ${Prompt[$i]};
    done;
}

play(){
    local res fc try move moves addr addrs rc=0;
	declare -au player=();   # Auto-convert to uppercase
	declare -au player_in=();
    
    prompt $PromptLevel;
    
	read -a player_in -r -e -p 'Enter your actions(s): ';

	## Check for empty input 
    [ yes = ${player_in[0]:-yes} ] && return $rc;

    player=${player_in[@]^^}	# upCase!

    for move in ${player[*]}; do
    
      ## Extract optional action first (last char)
      action=D						# default action
      try=${move:(-1)};
      for fc in M U D; do
        if [ $fc = $try  ]; then
          action=$try;
          break;
        fi
      done
      
      if [ $action = $try ]; then  # was explicit action
        move=${move:0:-1};         # strip action char
      fi

      addrs=$(addrParse $move);	   # expand address expression, if any
	  [ -z "$addrs" ] && echo "Bad cell address, Skipping \"$move\""  && continue;
      for addr in $addrs; do
#        echo $addr $action
	    ## Do one player command, returning if a detonation occurs
	    act $action $addr || return 1;
	  done
    done;
}


reinitGame(){
  initPlay;
  initCellMap;
}


initialize(){
  echo "Initializing...";
  initGeom $Width $Height;
  initPlay;
  initCell;
  declareCellMap "${RowRange[*]}" "${ColRange[*]}";
  initCellMap;
  initNav;
  initPrompt;
#  dumpMap;
}


# $1=cols
# $2=mode
render(){
  local cols=$1;
  local mode=$2;

  status $cols;
  header $cols;
  renderMap $mode;
  footer $cols;
}


options $*;
initialize;

## Main Loop ##
while [ 0 ]; do
#  dumpMap;
  render $Cols $Mode;
  while play && [ $Remaining -gt 0 ] && [ $Marks -ne $MineCount ]; do
  render $Cols $Mode;
    [ $Turns -eq 1 ] && dumpMapFile;
    (( Turns++ ));
  done
  render $Cols Reveal;
  if [ $Remaining -eq 0 ] || [ $Marks -eq $MineCount ] && [ $MisMarks -eq 0 ]; then
      MOOB;
  else
      [ $MisMarks -gt 0 ] && BOOM "$MisMarks Mis-Marked cell(s)";
      [ $MisMarks -eq 0 ] && BOOM "Bomb DETONATED!";
  fi
  sleep 3;
  read -N1 -i Y -r -p "Play again? :" yn;
  echo
  if [ ${yn^^} = Y ]; then
   reinitGame;
  else
    exit;
  fi;
done;
