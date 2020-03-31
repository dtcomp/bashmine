## Convert decimal number to ASCII char
## Ex: 65 -> 'A'
chr() {
  printf '%b'  $(printf '\\x%02x' $1);
}


## Convert an ASCII char to decimal number.
## Ex. 'A' -> 65
ord(){
  printf  '%d' "'$1";
}

## $1 = base ASCII Character
## Echos next character in sequence
## Or empty string if error
## Return code = 0 on success
## Otherwise, 1
succ(){
  [ -z "$1" ] && return 1;
  local o=$( ord "$1" );
  local d=$(( $o + 1 ));
  echo $( chr $d );
}

## Similar, as above
pred(){
  [ -z "$1" ] && return 1;
  local o=$( ord "$1" );
  local d=$(( $o - 1))
  echo $( chr $d )
}

inc(){
  echo $(( $1 + 1 ));
}

dec(){
  echo $(( $1 -1 ));
}

## Browse info array
## $1=screen lines
## $2=Name of global array to use
## $3=# of items/lines in array
inter(){
  local -i lines=$1;   # terminal lines to display
  local text=$2;       # name of text array
  local -i linecnt=$3; # lines of text (array size)
  local -u reply;      # uppercase
  local -i change=0;   # bool
  local ifs=$IFS	   # save field seperator
  local -i i
  local -i startline=0
  local -i stopline=$lines;

  for (( i=0; i<$linecnt; i++ )); do
    eval  "echo -n \${"${text}"[\$i]} >/dev/null;";
  done

#  echo lines= $lines    text= $text  linecnt= $linecnt
  for (( i=0; i<$lines; i++ )); do
    eval  "echo \${"${text}"[\$i]};";
    if [ $i -ge $linecnt ]; then break; fi
  done

  while [ 0 ]; do
  tput cup $lines 0
  echo -en "${Term[sto]}NextPage:<Space> PrevPage:b NextLine:<CR> PrevLine:p Quit: q${Term[sti]}"
  IFS=
  read -s -N 1 -r reply;
#  echo reply= $( ord "$reply" )
  case "$reply" in
  B)
    if [ $startline -gt 0 ]; then
      (( startline-=$lines ));
      (( stopline-=$lines  ));
      if [ $startline -lt 0 ]; then  startline=0; stopline=$lines; fi
      change=0;
    else
      change=1;
    fi
    ;;
  ' ')
    if [ $stopline -lt $linecnt ]; then
      (( stopline+=lines ));
      startline=$(( stopline-lines ));
      if [ $stopline -gt $linecnt ]; then stopline=$linecnt; startline=$(( linecnt-lines )); fi
      change=0;
    else
      change=1;
    fi
    ;;
   P)
    if [ $(( startline )) -gt 0 ]; then
      (( startline-- ));
      (( stopline-- ));
      change=0;
    else
      change=1;
    fi
    ;;
  Q)
    IFS=$ifs;
    echo;
    return;
    ;;
  *)
    if [ $(( startline+lines )) -lt $linecnt ]; then
      (( startline++ ));
      (( stopline++ ));
      change=0;
    else
      change=1;
    fi
  esac;
  if [ $change ]; then
  tput clear
  tput cup 0 0
  for (( i=$startline; i<$stopline; i++ )); do
    eval "echo -n \${"${text}"[\$i]};";
    if [ $i -ge $linecnt ]; then break; fi
  done
  fi
  done
}


