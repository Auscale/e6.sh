#!/bin/bash

# https://e621.net/
# Original script by: /u/BASH_SCRIPTS_FOR_YOU
# Revised by /u/Auscale
# GPLv3 or later

# TODO: Add extra filtering on data that we get from the API. Will allow things like:
#   Extra tags
#   Fav / Score
#   Width / Height
#   File size
#   Rating

echo "Script initiated - $(date)"

args=("$@")

# output help if user asks for it, or if user provides no arguments
if [ $# = 0 ] || [ $1 = "--help" ] ; then
  echo "e6.sh"
  echo ""
  echo "Usage: ./e6.sh [OPTION]... [DIRECTORY]..."
  echo "Downlods files into specified directories, relative to the script location."
  echo ""
  echo "Options:"
  echo "-a  =  all           runs for every directory found"
  echo "-d  =  duplicate     will not check every directory for a file before downloading it"
  echo "-c  =  continue      will attempt to use an existing list of links to resume donwloading, if it fails, it falls back to normal"
  echo "-t  =  tag           prompts for tags, even if a tag file exists"
  echo "-q  =  quiet         only outputs for downloaded images and errors, quits if input is required"
  echo "--help               shows this text"
  echo ""
  echo "Examples:"
  echo "  $ ./e6.sh felines"
  echo "  Please enter your tag string for directory: ./felines"
  echo "  female feline rating:s absurd_res"
  echo ""
  echo "This will download every file from e621 tagged with "female", "feline", "absurd_res" and marked as SFW."
  echo "If the felines directory does not exist, it is created, and two files are created inside:"
  echo "  tags  - stores the tag information you enter."
  echo "  links - stores the direct image links to e621."
  echo "If you need to cancel the download and continue later, you can specify the -c flag next time you run it:"
  echo "  $ ./e6.sh -c felines"
  echo "This will avoid re-downloading the image list, which saves a bit of time. However, you will not get any images that have been uploaded or re-tagged since you generated the list."
  echo ""
  echo "You can specify multiple directories at once:"
  echo "  $ ./e6.sh felines canines dragons other"
  echo "Or use the -a flag to run for every directory."
  echo "If you ever want to edit your tags, use the -t flag."
  echo "If you leave the tags blank, no tag file will be created. If one previously existed, it will be used to generate a new list. If one does not exist, no list is generated, and no files are downloaded."
  echo "This script will never delete files, so if it downloads an incorrectly tagged file, you will have to manually delete it, even if it gets tagged correctly in the future."
  echo "By default, the script will check all other directories for duplicates, and avoid downloading them. To override this behaviour, use the -d flag."
  echo ""
  echo "In the future, I hope to provide a way to filter on extra information, such as Favcount / Score, Width / Height, Filesize, Rating and provide extra tag filtering."
  echo "This can still be done using tags, but you only get 6 as an anonymous user. There is a way to log in using the API, which may provide additional tags. I'm not sure. That'll be coming in a later version too."
  echo ""
  echo "Shoutout to /u/BASH_SCRIPTS_FOR_YOU for the original script. Sadly it stopped working when e621 changed the JSON on their post pages. This hopefully improved version builds on the functionality and utilises e621's XML API, so it should be slightly faster to
generate links."
  echo "Happy Yiffing!"
  echo "Updated: 07/02/16"
  exit
fi

# constants
API="https://e621.net/post/index.xml?"
LIMIT="100"

# generate variables based on passed arguments
if [ $(echo "$1" | grep -ce '^-\w*a') -ge 1 ] ; then
  flags_a=true
fi

if [ $(echo "$1" | grep -ce '^-\w*d') -ge 1 ] ; then
  flags_d=true
fi

if [ $(echo "$1" | grep -ce '^-\w*c') -ge 1 ] ; then
  flags_c=true
fi

if [ $(echo "$1" | grep -ce '^-\w*t') -ge 1 ] ; then
  flags_t=true
fi

if [ $(echo "$1" | grep -ce '^-\w*q') -ge 1 ] ; then
  flags_q=true
fi

# get array of directories to loop through
if [ "$flags_a" = true ] ; then

  for d in */ ; do
    dir_array+=("$d")
  done

  if [ ${#dir_array[@]} = 0 ] ; then
    echo "-a flag specified, but no directories found. Use --help for help."
    exit
  fi
else

  for arg in "$@"; do
    if [ $(echo "$arg" | grep -ce '^-') = 0 ] ; then
      dir_array+=("./$arg")
    fi
  done

  if [ ${#dir_array[@]} = 0 ] ; then
    echo "You must specify a directory. Use --help for help."
    exit
  fi

  # loop over given directories, creating them if they don't exist.
  for dir in "${dir_array[@]}"; do
    if [ ! -d "$dir" ] ; then
      mkdir "$dir"
    fi
  done

fi

# create our tag files within each directory, if (they don't exist, or if -t is specified) and -q is not
for dir in "${dir_array[@]}"; do
  if [[ ! -f "$dir/tags" || "$flags_t" = true ]] && [ -z "$flags_q" ] ; then
    echo "Please enter your tag string for directory: $dir"
    read tags
    if [ -z "$tags" ] ; then
      echo "No tags entered for $dir. Skipping."
    else
      echo "$tags" > "$dir/tags"
    fi
  fi
done

# create link files
for dir in "${dir_array[@]}"; do
  if [ -f "$dir/tags" ] ; then
    if [ -z "$flags_c" ] || [[ "$flags_c" = true && ! -f "$dir/links" ]] ; then

      tags=`cat $dir/tags`
      if [ -z "$flags_q" ] ; then
        echo "Creating link file for $dir. Calculating pages..."
      fi
      files=`curl --retry 8 -s -g "${API}limit=1&page=0&tags=${tags// /%20}" | grep -oP 'posts count="\d+"' | grep -oP '\d+'`
      pages=$(((files + (LIMIT - 1)) / LIMIT))

      if [ "$pages" = 1 ] ; then
        plural_page="page"
      else
        plural_page="pages"
      fi

      if [ "$files" = 1 ] ; then
        plural_file="file"
      else
        plural_file="files"
      fi

      if [ -z "$flags_q" ] ; then
        echo "$files $plural_file over $pages $plural_page at $LIMIT files per page."
      fi

      page=0
      cp /dev/null "${dir}/links"

      while [ "$page" != "$pages" ]
        do page=$(( ${page} + 1 ))
        if [ -z "$flags_q" ] ; then
          echo "Page $page of $pages."
        fi
        # This kinda sucks, but it's the best I got. Grabs source, strips out file_url text, then strips out only the link, then splits spaces to newlines, then writes to file.
        echo $(curl -s -g "${API}limit=${LIMIT}&page=${page}&tags=${tags// /%20}" | grep -oP 'file_url>.*?<' | grep -oe 'http.*[^<]') | tr " " "\n" >> "${dir}/links"
      done
    else
      if [ -z "$flags_q" ] ; then
        echo "Link file exists for $dir. Skipping."
      fi
    fi
  fi
done

# download files
for dir in "${dir_array[@]}"; do
  if [ -f "$dir/links" ] ; then
    if [ -z "$flags_q" ] ; then
      echo "Downloading files for $dir"
    fi
    linenumber=0
    lines=`cat $dir/links | wc -l`
    while [ "${lines}" != "${linenumber}" ] ; do
      skip=false
      linenumber=$(( ${linenumber} + 1 ))
      link=$(sed "${linenumber}q;d" "$dir/links")
      file=$(echo $link | grep -o '[^\/]*$')
      if [ "$flags_d" = true ] ; then
        if [ -f "$dir/$file" ] ; then
          if [ -z "$flags_q" ] ; then
            echo "File $file found, skipping."
          fi
          skip=true
        fi
      else
      for subdir in "${dir_array[@]}"; do
          if [ -f "$subdir/$file" ] ; then
            if [ -z "$flags_q" ] ; then
              echo "File $file found in $subdir using global search. Skipping"
            fi
            skip=true
            break
          fi
        done
      fi
      if [ "$skip" = false ] ; then
        if [ -z "$flags_q" ] ; then
          echo "Downloading file $linenumber of $lines."
          curl -# ${link} > ${dir}/${file}
        else
          echo "Downloaded file $file to $dir"
          curl -s ${link} > ${dir}/${file}
        fi
      fi
    done
  fi
done
echo "Script completed successfully - $(date)"
exit
