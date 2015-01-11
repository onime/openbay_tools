#!/bin/sh

# script pour normaliser les noms des torrents 

function usage
{
    echo "usage: normalize.sh [option] file[.gz]"
}

function free_tmp_file
{
    mv $1 $2
    wc -lc $2
    echo "  "$(cat $2 | egrep '^"? *"?$' | wc -l) empty lines
}

function purge_bad_lines
{
    # recupere seulement les lignes formé. on exclue les lignes qui ne comporte pas de magnet|categorie|...|...
    
    echo "Supprime les lignes malformées (peut prendre du temps)"
    egrep -i "^.*\|[0-9]+\|[0-9a-f]+\|[0-9]+\|.+\|[0-9]+\|[0-9]+$" $1 > tmp_openbay_torrents_purge_bad_lines
    free_tmp_file tmp_openbay_torrents_purge_bad_lines $1

    echo "Remplace \"series & tv\" par shows-tv"
    sed 's/|"series & tv"|/|shows-tv|/' < $1 > tmp_opb_replace_shows
    free_tmp_file tmp_opb_replace_shows $1
}

# extrait le nom de chaque torrent
function extract_name
{
    echo "Extract name from $file"

    rev $1 | cut -d'|' -f7- |rev > $2
    rev $1 | cut -d'|' -f1-6 |rev > $3
    wc -lc $2
    echo "  "$(egrep "^ *$" $2 | wc -l) empty lines
}

function rm_pipe
{
    echo "Remplace les pipes par des '-'"
    # cat $file | sed 's/|/-/g' >  openbay_anime_name_normalize
    tr '|' '-' < $1 > openbay_anime_name_normalize
    free_tmp_file openbay_anime_name_normalize $1
}

# supprime les tags html, les liens https,
function rm_webinfo
{
    echo "Decode les caractère spéciaux éèà&"
    #use recode instead
    sed -e 's/&eacute/é/g' -e 's/&eagrave/è/g' -e 's/&agrave/à/g' -e 's/&amp/\&/g' < $1 > tmp_opb_specialchars
    free_tmp_file tmp_opb_specialchars $1

    echo "Decode les url %5b %20 ..."

    perl -pe 's/\%([a-f2-9][a-f0-9])/chr hex $1/gei' < $1 >tmp_opb_entities
    free_tmp_file tmp_opb_entities $1

    echo "Supprime les tags html"
    sed 's/<[^<]*>//g' < $1  > tmp_opb_rm_html_tags
    free_tmp_file tmp_opb_rm_html_tags $1

    echo "Supprime les liens http(s)/www"
    sed -r 's#(https?(://| +)?(www)?|www)([-?&=/.a-z0-9 ]+)?##g' < $1 > tmp_opb_without_http_link
    free_tmp_file tmp_opb_without_http_link $1
}

function rm_path
{
    echo "Suppprime les chemins C:\ et /home/..."
    sed -e 's/C:[\].*[\]//g' -e  's/C:.* //g' -e 's#/home/.*/##g' < $1 > tmp_opb_without_pathlink
    free_tmp_file tmp_opb_without_pathlink $1
}

function rm_brackets
{
    echo "Supprime les [.*] et (.*)"

    sed -re 's/\[[^[]*\]//g' -e 's/[(][^(]*[)]//g' < $1 > tmp_opb_without_brackets
    free_tmp_file tmp_opb_without_brackets $1
}

function rm_tags
{
    echo "Supprime les TAGS (ex : HDTV|READNFO|PROPER...)"
    # garder 720p pour avoir l'information sur l'encodage, english subs et autre sous-titre CAM et dvdrip
    sed -r 's/[. ]avi|dht only|trackerless|x264|READNFO|Blueray|DIVX5|REMUX|dxva|AAC|AC3|1920x1080|PROPER|XVID|unrated|hdtv|PDTV|xvid-(WATERS|SUNSPOT|Larency|universal|imagine)//ig' < $1 > tmp_opb_without_TAGS
    free_tmp_file tmp_opb_without_TAGS $1
}

function rm_multiple_punct
{
    echo "Supprime les ponctuations inutiles"
    #Attention cette opération supprime les " de début et fin
    #on remplace les multiples espaces dans 's/ +/ /g' et non dans 's/[[:punct:]]+/-/g' pour eviter de n'avoir que des '-' dans chaque ligne

    sed -re 's/[[:punct:]]+/-/g' -e 's/ +/ /g' -e 's/^[- ]+//' -e 's/[- ]+$//' < $1 > tmp_opb_without_multiple_punct
    free_tmp_file tmp_opb_without_multiple_punct $1
}

function add_start_end_quotes
{
    echo "Rajoute des quotes au début et à la fin de chaque ligne"
    sed 's/^.*$/"&"/' < $1 > tmp_opb_add_quotes
    free_tmp_file tmp_opb_add_quotes $1
}

function join_files
{
    nl -w 1 -s'|' $2  > tmp_join_name
    nl -w 1 -s'|' $3  > tmp_join_tail
    
    join -t'|' tmp_join_name tmp_join_tail > $1
    rm tmp_*
    sed -r 's/^[0-9]+[|]//' < $1 > tmp_remove_nl
    
    free_tmp_file tmp_remove_nl $1
}

function rm_empty_name
{
    echo "Supprime les lignes dont le nom est vide"
    grep -v '^""|.*' $1 > tmp_rm_empty_lines
    free_tmp_file tmp_rm_empty_lines $1
}

if [ $# -eq 0 ]
then
    usage
    exit 1
fi

if [ $# -gt 1 ]
then
    if [ $1 == "--split-category" ]
    then

	if [ ! -f $2 ]
	then
	    usage
	    echo "$0: '$2' is not a file"
	    exit 1
	fi
	
	main_file=$2

	if [ $(file $main_file | grep compressed | wc -l) -ge 1 ]
	then
	    zcat $main_file > $main_file"_dump"
	fi

    	#purge_bad_lines $main_file	
	#on obtient les categories avec la commande 
	#cat $2 | rev | cut -d'|' -f3 | sort |uniq | rev > openbay_categories
	#mais elle met bien trop de temps à s'executer
	#j'ai aussi changé "series & tv" en tv-shows car ça n'avait pas de sens à mon avis
	categories='music anime software other movies games books adult shows-tv'
	for i in $categories
	do
	    echo -n "Extracting $i..."
	#    egrep "\|$i\|[0-9]+\|[0-9]+" $main_file > openbay_$i.csv
	    echo " done."
	    sleep 0.2
	done
	files=$(ls openbay_* | grep -v $main_file)
    elif [ $1 == "--import-mongodb" ]
    then
	echo "importing"
	# changer les pipes en ',' et avertir qu'il faut d'abbord avoir normalisé sinon ça peut mal séparer

    else
	usage
	exit 1
    fi
    
else
    if [ ! -f $1 ]
    then
	usage
	echo "$0: '$1' is not a file"
	exit 1
    fi
    main_file=$1
    files=$main_file
    #purge_bad_lines $main_file
fi

exit 1

for file in $files
do

    echo -e "\n$file..."
    file_name="name_$file"
    file_tail="tail_$file"

    nb_bytes=$(ls -lh $file | awk '{print $5}')

    extract_name $file $file_name $file_tail
    rm_pipe $file_name
    rm_webinfo $file_name
    rm_path $file_name
    rm_brackets $file_name
    rm_tags $file_name
    rm_multiple_punct $file_name
    add_start_end_quotes $file_name

    join_files $file $file_name $file_tail
    rm_empty_name $file

    rm $file_name $file_tail

    nb_bytes_new=$(ls -lh $file | awk '{print $5}')
    echo -e "\nold $file: $nb_bytes, new $file: $nb_bytes_new"

    sleep 0.2

done
