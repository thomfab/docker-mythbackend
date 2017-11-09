#!/bin/bash
# @(#)$Header: /home/mythtv/mythtvrep/scripts/mythnuv2mkv.sh,v 1.61 2010/10/09 21:06:19 mythtv Exp $
# Auric 2007/07/10 http://web.aanet.com.au/auric/
# source the config file
[ -f $(dirname "$0")/mythnuv2mkv.cfg ] && . $(dirname "$0")/mythnuv2mkv.cfg

##########################################################################################################
#
# Convert MythRecording & MythVideo nuv or mpg files to mkv mp4 or avi.
#
######### Vars you may want to set for your environment, put them in mythnuv2mkv.cfg along with this script ##

# Default aspect for Myth Recording mpg files. It will try to work it out but if it can't will use this.
readonly DEFAULTMPEG2ASPECT="${DEFAULTMPEG2ASPECT-NA}" # 4:3 or 16:9
# Log directory
readonly LOGBASEDIR="${LOGBASEDIR-/var/tmp}" # Don't use a directory with spaces in it's name
# Number of errors reported by mplayer allowed in the transcoded file
readonly MPLAYER_ERROR_COUNT="${MPLAYER_ERROR_COUNT-8}"
# Path to your mysql.txt file
readonly MYSQLTXT="${MYSQLTXT-}"
# What to separate title, subtitle etc. with
readonly SEP="${SEP-,}"
# What (if at all) to replace spaces with
readonly TR="${TR-_}"
# printf(episode_number)
readonly EPISODE_FORMAT="${EPISODE_FORMAT-E%02d}"
# printf(formatted_episode, season_number)
readonly SEASON_FORMAT="${SEASON_FORMAT-S%2\$02d%1\$s }"
# printf(title, formatted_season_episode)
readonly TITLE_FORMAT="${TITLE_FORMAT-%s %s}"
# printf(filename, date)
readonly DATE_FORMAT="${DATE_FORMAT-%s [%s]}"
# RegEx for matching season/episode numbers
readonly EPISODE_RE="${EPISODE_RE-^S[0-9]+E[0-9]+ $}"
# Chapter marks every X minutes
CHAPTERDURATION="${CHAPTERDURATION-0}"
# Crop input
CROP="${CROP-ON}" # ON | OFF, can also change with --crop argument
CROPSIZE="${CROPSIZE-8}"
# Delete recording after successful transcode. Only for transcode out of MythRecording. (Actually just sets to high priority autoexpire.)
DELETEREC="${DELETEREC-OFF}" # ON | OFF, can also change with --deleterec argument
# Include denoise filter
DENOISE="${DENOISE-OFF}" # ON | OFF, can also change with --denoise argument
# Include deblock filter
DEBLOCK="${DEBLOCK-OFF}" # ON | OFF, can also change with --deblock argument
# Include deinterlace filter.
# SOURCENAME is ON for that source. Can have multiple. e.g. DEINTERLACE="Cabel,FTA1"
DEINTERLACE="${DEINTERLACE-ON}" # ON | OFF | SOURCENAME,SOURCENAME can also change with --deinterlace argument.
# Include inverse Telecine filter (Experimental. Can someone from NTSC/ATSC land try this?).
# invtelecine filter is never added if deinterlace has been added.
INVTELECINE="${INVTELECINE-OFF}" # ON | OFF, can also change with --invtelecine argument.
# number passes
PASS="${PASS-two}" # one | two, can also change with --pass argument
# number of threads. Only used by lavc and xvid (x.264 auto calculates threads)
THREADS="${THREADS-1}"
# avi encoder lavc or xvid
AVIVID="${AVIVID-lavc}" # lavc | xvid, can also change with --contype=avi,xvid argument
# container
CONTYPE="${CONTYPE-mkv}" # mkv | mp4 | avi, can also change with --contype argument or name of script.
# mkv audio encoder aac or ogg
MKVAUD="${MKVAUD-aac}" # aac | ogg, can also change with --contype=mkv,ogg argument
# audio tracks with, optionally, their language code, in the order they are to be added to the resulting file
# language codes and multiple tracks only supported in mp4 and mkv
ATRACKS="${ATRACKS-0}" # n[:lng][,m[:lng]]..., can also change with --audiotracks
# add your own filters if you want
POSTVIDFILTERS="${POSTVIDFILTERS-}"	#must include , at end
ENDVIDFILTERS="${ENDVIDFILTERS-}"	#must include , at end
# Disable some output checks. Can have multiple. e.g. OUTPUTCHECKS="NOSIZERATIO,NOSCAN"
OUTPUTCHECKS="${OUTPUTCHEKS-}" # NOSIZE,NOVIDINFO,NOSIZERATIO,NOFRAMECOUNT,NOSCAN can also change with --outputchecks argument.
# Boinc passwd, if you run boinc and want to disable it during transcode
readonly BOINCPASSWD="${BOINCPASSWD-}"
# Use mediainfo if available to identify video properties.
USEMEDIAINFO="${USEMEDIAINFO-TRUE}" # TRUE or FALSE
# default quality profile
QUALITY="${QUALITY-med}"

#
PATH=~mythtv/bin:${HOME}/bin:$PATH:/usr/local/bin
# these variables will be recalled, if temporarily overriden, on every file change
RECALL="ASPECTINLINE DENOISE POSTVIDFILTERS DEBLOCK DEINTERLACE INVTELECINE CROP CROPSIZE DELETEREC CHAPTERDURATION \
CHAPTERFILE COPYDIR CONTYPE QUICKTIME_MP4 MKVAUD AVIVID PASS SCALE43 SCALE169 LAVC_CQ LAVC_OPTS XVID_CQ XVID_OPTS \
MP3_ABITRATE X264_CQ X264EXT_OPTS X264_OPTS AAC_AQUAL OGG_AQUAL ATRACKS TITLE SUBTITLE"
# these variables will be clean on every file change
CLEAN="META_SEASON META_EPISODE META_ARTIST META_DIRECTOR META_ALBUM META_COMMENT META_LOCATION META_DATE"


##### Mapping #############################################################################################
# Maps tvguide categories to mythvideo ones. This will need to be managed individually.
# Either use the defaults below or create a mythnuv2mkv-category-mappings file in the same
# directory as this and enter data same format as below.
readonly CMAPFILE="$(dirname ${0})/mythnuv2mkv-category-mappings"
if [ -f "$CMAPFILE" ]
then
	. "$CMAPFILE"
else
	# NOTE: Remove any spaces from XMLTV category. e.g. "Mystery and Suspense" is MysteryandSuspense
	# XMLTV Category		 ; Myth videocategory
	readonly Animated=1		 ; mythcat[1]="Animation"
	readonly Biography=2		 ; mythcat[2]="Documentary"
	readonly Historical=3		 ; mythcat[3]="Documentary"
	readonly CrimeDrama=4		 ; mythcat[4]="CrimeDrama"
	readonly MysteryandSuspense=5	 ; mythcat[5]="Mystery"
	readonly Technology=6		 ; mythcat[6]="Documentary"
	readonly ScienceFiction=7	 ; mythcat[7]="Sci-Fi"
	readonly Science_Fiction=8	 ; mythcat[8]="Sci-Fi"
	readonly art=9			 ; mythcat[9]="Musical"
	readonly History=10		 ; mythcat[10]="Documentary"
	readonly SciFi=11		 ; mythcat[11]="Sci-Fi"
	readonly ScienceNature=12	 ; mythcat[12]="Science"
fi

##########################################################################################################
USAGE='mythnuv2mkv.sh [--jobid=%JOBID%] [--contype=avi|mkv|mp4] [--quality=low|med|high|480|576|720|1080] [--pass=one|two] [--denoise=ON|OFF] [--deblock=ON|OFF] [--deleterec=ON|OFF] [--aspect=4:3|16:9] [--crop=ON|OFF] [--deinterlace=ON|OFF|SOURCENAME] [--invtelecine=ON|OFF] [--outputchecks=notype] [[--chapterduration=mins] | [--chapterfile=file]] [--maxrunhours=int] [--findtitle=string] [--copydir=directory] "--chanid=chanid --starttime=starttime" | file ...
Must have either --chanid=chanid and --starttime=starttime or a plain filename. These can be mixed. e.g. -
mythnuv2mkv.sh --chanid=1232 --starttime=20071231235900 video1 video2 --chanid=1235 --starttime=20071231205900
--jobid=%JOBID%
        Add this when run as a User Job. Enables update status in the System Status Job Queue screen and the Job Queue Comments field in MythWeb. Also enables stop/pause/resume of job.
--contype=avi|mkv|mp4 (default name of script. e.g. mythnuv2mkv.sh will default to mkv. mythnuv2avi.sh will default to avi)
	(Note Videos staying in MythRecord will always default to avi)
	avi - Video mpeg4 Audio mp3 (--contype=avi,xvid will use xvid instead of lavc)
	mkv - Video h.264 Audio aac (--contype=mkv,ogg will use ogg Vorbis Audio)
	mp4 - Video h.264 Audio aac
--quality=low|med|high|720|1080 (default med) Mostly affects resolution.
	low  - 448x336(4:3) or 592x336(16:9)
	med  - 512x384(4:3) or 624x352(16:9)
	high - 528x400(4:3) or 656x368(16:9)
	480  - 640x480(4:3) or 848x480(16:9)
	576  - 768x576(4:3) or 1024x576(16:9)
	720  - 1280x720(16:9) (You probably need VDAPU to play this)
	1080 - 1920x1088(16:9) (You probably need VDAPU to play this)
--pass=one|two (default two)
	--quality --pass and --contype can be passed as any argument and will only take effect on files after them.
	e.g. mythnuv2mkv.sh videofile1 --chanid=2033 --starttime=20070704135700 --pass=one video3 --quality=low video4
	videofile1 and chanid=2033/starttime=20070704135700 will be two pass med quality (defaults)
	video3, one pass med quality
	video4, one pass low quality
--audiotracks=n[:lng][,m[:lng]]... (default empty)
	audio tracks and, optionally, their language code, in the order they are supposed to be added to the output file (language codes and multiple tracks only supported in mp4 and mkv),
	empty means one track, whichever mythtranscode chooses by default
--maxrunhours=int (default process all files)
	Stop processing files after int hours. (Will complete the current file it is processing.)
--findtitle="string"
	Prints tile, chanid, starttime of programs matching string.
--copydir=directory
	mkv/mp4/avi file will be created in directory. Source nuv will be retained. i.e you are copying the source rather than replacing it.
	If the source was a CHANID/STARTIME it will be renamed to TITLE,S##E##,SUBTITLE. S##E## is the Season and Episode number. All punctuation characters are removed.
	For MythTV 0.21 - If directory is under MythVideoDir, imdb will be searched, a MythVideo db entry created and a coverfile file created if one was not available at imdb.
	For MythTV 0.22 - If directory is under MythVideoDir, no action taken. Use MythVideo tools, e.g. Metadata menu, jamu.
--denoise=[ON|OFF] (default OFF)
	Include hqdn3d denoise filter.
--deblock=[ON|OFF] (default OFF)
	Include pp7 deblock filter.
--deleterec=[ON|OFF] (default OFF)
	Delete the recording after successful transcode. (Actually just sets high priority autoexpire and moves to Deleted group.)
--crop=[ON|OFF] (default ON)
	Crop 8 pixels of each side.
--aspect=[4:3|16:9] Force aspect.
--deinterlace==[ON|OFF|SOURCENAME] (default ON)
	Include pp=fd deinterlace filter.
	SOURCENAME is ON for that source. Can have multiple. e.g. DEINTERLACE="Cabel,FTA1"
--invtelecine=[ON|OFF] (default OFF)
	Include pullup inverse telecine filter.
	Note/ This filter will not be added if a deinterlace filter has been added.
--outputchecks=[NOSIZE,NOVIDINFO,NOSIZERATIO,NOFRAMECOUNT,NOSCAN] (default All checks ON)
	Disable a output check. Set to one or many of the checks. e.g. OUTPUTCHECKS="NOSIZERATIO,NOSCAN"
---chapterduration=mins
	Add chapter marks to mkv/mp4 files every mins minutes.
---chapterfile=file
	Add chapter marks to mkv/mp4 as per chapter file. See mkvmerge or MP4Box manual for chapter file format.
	(spaces not supported in chapter file name)

Logs to /var/tmp/mythnuv2mkvPID.log and to database if "log MythTV events to database" is enabled in mythtv.
Cutlists are always honored.
Sending the mythnuv2mkv.sh process a USR1 signal will cause it to stop after completing the current file.
e.g. kill -s USR1 PID
If run as a Myth Job, you can find the PID in the System Status Job Queue or Log Entries screens as [PID]

Typical usage.

Myth User Job
PATH/mythnuv2mkv.sh --jobid=%JOBID% --copydir /mythvideodirectory --chanid=%CHANID% --starttime=%STARTTIME%
This will convert nuv to mkv and copy it to /mythvideodirectory.
This is what I do. Record things in Myth Recording and anything I want to keep, use this to convert to mkv and store in Myth Video.
NOTE. System Status Job Queue screen and the Job Queue Comments field in MythWeb always report job Completed Successfully even if it actually failed.

Myth Video
Record program
mythrename.pl --link --format %T-%S --underscores --verbose (mythrename.pl is in the mythtv contrib directory
cp from your mythstore/show_names/PROGRAM to your MythVideo directory
use video manager to add imdb details
nuv files work fine in MythVideo, but if you need to convert them to mkv/mp4/avi, or need to reduce their size
run mythnuv2mkv.sh MythVideo_file.nuv

Myth Recording
Record program
run mythnuv2mkv.sh --findtitle="title name"
get chanid and starttime
run mythnuv2mkv.sh --chanid=chanid --starttime=starttime
NOTE You cannot edit a avi/mp4/mkv file in Myth Recording. So do all your editing in the nuv file before you convert to avi.
NOTE You cannot play a mkv/mp4 file in Myth Recording.
I would in general recommend leaving everything in Myth Recording as nuv.

You can override most options for a specific recording by adding tags to the subtitle in MythTV, for example a subtitle of the form:
  "Some subtitle r|David Lynch q|1080 f|mp4 crop|NO"
  Will result in:
    - subtitle:"Some subtitle"
    - director: "David Lynch"
    - quality: 1080
    - container: mp4
    - crop: NO
  Available tags:
    t: title
    s: subtitle / episode title
    n: season number
    e: episode number
    a: artist
    r: director
    b: album
    c: comment
    l: location
    y|d: year / date (YYYY / YYYY-MM-DD / DD-MM-YYYY / DD.MM.YYYY etc.)
    q: quality
    f: container format
    aud: audio track definitions
    asp: aspect ratio
    den: denoise filter
    deb: deblock filter
    dei: deinterlace
    inv: inverse telecine
    crop: cropping
    del: delete recording
    chap: chapter length
    chapf: chapter file
    dir: copy directory
    pass: encoding pass count

Version: $Revision: 1.91 (beta) $ $Date: 2011/03/23 01:13:12 $
'
REQUIREDAPPS='
Required Applications
For all contypes
mythtranscode.
perl
mplayer http://www.mplayerhq.hu/design7/news.html
mencoder http://www.mplayerhq.hu/design7/news.html
wget http://www.gnu.org/software/wget/
ImageMagick http://www.imagemagick.org/script/index.php
For avi
mp3lame http://www.mp3dev.org
xvid http://www.xvid.org/
For mkv and mp4 contypes
x264 http://www.videolan.org/developers/x264.html
faac http://sourceforge.net/projects/faac/
faad2 http://sourceforge.net/projects/faac/
For mkv contype
mkvtoolnix http://www.bunkus.org/videotools/mkvtoolnix/
For mkv,ogg contype
vorbis-tools http://www.vorbis.com/
For mp4 contype
MP4Box http://gpac.sourceforge.net/index.php
'
HELP=${USAGE}${REQUIREDAPPS}

##### Pre Functions ###########################################
preversioncheck() {
local PRODUCT="$1"
local LIBX264
	case $PRODUCT in
		libx264)
			LIBX264=$(ldd $(which mencoder) | awk '/libx264/ {print $3}')
			if strings "$LIBX264" | grep MB-tree >/dev/null 2>&1
			then
				# Actually won't be used as currently (23/11/09) b_pyramid is disabled when MB-tree used
				# At some point b_pyramid may be added, so leaving this in
				NOBPYRAMID="b_pyramid=none:" # Global
				BPYRAMID="b_pyramid=normal:" # Global
			else
				NOBPYRAMID="nob_pyramid:" # Global
				BPYRAMID="b_pyramid:" # Global
			fi
			if strings "$LIBX264" | grep force-cfr >/dev/null 2>&1
			then
				FORCECFR="force_cfr:" # Global
			else
				FORCECFR="" # Global
			fi
               ;;
	esac
}

###########################################################
readonly AVIREQPROGS="mencoder mythtranscode mplayer perl wget convert"
readonly AVIREQLIBS="libmp3lame.so libxvidcore.so"
readonly MP4REQPROGS="mencoder mythtranscode mplayer perl wget convert faac MP4Box"
readonly MP4REQLIBS="libx264.so"
readonly MKVREQPROGS="mencoder mythtranscode mplayer perl wget convert faac oggenc mkvmerge"
readonly MKVREQLIBS="libx264.so"
###########################################################
readonly DENOISEFILTER="hqdn3d"
readonly DEBLOCKFILTER="pp7"
readonly DEINTERLACEFILTER="pp=fd"
readonly INVTELECINEFILTER="pullup"
readonly FAACCHANCONFIG="-I 5,6"
readonly TE_SCALE43="NA"		# NA
readonly ST_SCALE43="NA"		# NA
readonly FE_SCALE43="640:480"		# 1.32
readonly FS_SCALE43="768:576"		# 1.32
readonly HIGH_SCALE43=528:400		# 1.32
readonly MED_SCALE43=512:384		# 1.333
readonly LOW_SCALE43=448:336		# 1.333
readonly TE_SCALE169="1920:1088" 	# 1.778
readonly ST_SCALE169="1280:720"		# 1.778
readonly FE_SCALE169="848:480" 		# 1.766
readonly FS_SCALE169="1024:576" 	# 1.778
readonly HIGH_SCALE169=656:368		# 1.783
readonly MED_SCALE169=624:352		# 1.773
readonly LOW_SCALE169=592:336		# 1.762
# Default
SCALE43=$MED_SCALE43
SCALE169=$MED_SCALE169
###########################################################
## CQ ## Quote from mencoder documentation
#The CQ depends on the bitrate, the video codec efficiency and the movie resolution. In order to raise the CQ, typically you would
#downscale the movie given that the bitrate is computed in function of the target size and the length of the movie, which are constant.
#With MPEG-4 ASP codecs such as Xvid and libavcodec, a CQ below 0.18 usually results in a pretty blocky picture, because there are
#not enough bits to code the information of each macroblock. (MPEG4, like many other codecs, groups pixels by blocks of several pixels
#to compress the image; if there are not enough bits, the edges of those blocks are visible.) It is therefore wise to take a CQ ranging
# from 0.20 to 0.22 for a 1 CD rip, and 0.26-0.28 for 2 CDs rip with standard encoding options. More advanced encoding options such as
#those listed here for libavcodec and Xvid should make it possible to get the same quality with CQ ranging from 0.18 to 0.20 for a 1 CD
#rip, and 0.24 to 0.26 for a 2 CD rip. With MPEG-4 AVC codecs such as x264, you can use a CQ ranging from 0.14 to 0.16 with standard
#encoding options, and should be able to go as low as 0.10 to 0.12 with x264's advanced encoding settings.
########################
# These map to --quality=low|med|high option.
#### AVI lavc mpeg4 ####
readonly HIGH_LAVC_CQ=0.22
readonly MED_LAVC_CQ=0.21
readonly LOW_LAVC_CQ=0.20
readonly HIGH_LAVC_OPTS="vcodec=mpeg4:threads=${THREADS}:mbd=2:trell:v4mv:last_pred=2:dia=-1:vmax_b_frames=2:vb_strategy=1:cmp=3:subcmp=3:precmp=0:vqcomp=0.6"
# high, med & low will use same settings just CQ and resolution different
# This make encoding slow. Swap following if you want lower quality to also mean faster encoding speed.
#readonly MED_LAVC_OPTS="vcodec=mpeg4:mbd=2:trell:v4mv"
#readonly LOW_LAVC_OPTS="vcodec=mpeg4:mbd=2"
readonly MED_LAVC_OPTS="$HIGH_LAVC_OPTS"
readonly LOW_LAVC_OPTS="$HIGH_LAVC_OPTS"
#### AVI xvid mpeg4 ####
readonly HIGH_XVID_CQ=0.22
readonly MED_XVID_CQ=0.21
readonly LOW_XVID_CQ=0.20
readonly HIGH_XVID_OPTS="threads=${THREADS}:quant_type=mpeg:me_quality=6:chroma_me:chroma_opt:trellis:hq_ac:vhq=4:bvhq=1"
readonly MED_XVID_OPTS="$HIGH_XVID_OPTS"
readonly LOW_XVID_OPTS="$HIGH_XVID_OPTS"
#### AVI lavc/xvid mp3 ####
readonly HIGH_MP3_ABITRATE=256
readonly MED_MP3_ABITRATE=192
readonly LOW_MP3_ABITRATE=128
#### MP4/MKV h.263/aac,ogg ####
readonly HIGH_X264_CQ=0.15
readonly MED_X264_CQ=0.14
readonly LOW_X264_CQ=0.13
preversioncheck "libx264" # Sets BPYRAMID & NOBPYRAMID & FORCECFR
# H.264 Extended profile (quicktime) level set in QLEVEL
readonly HIGH_X264EXT_OPTS="nocabac:bframes=2:${FORCECFR}${NOBPYRAMID}threads=auto:direct_pred=auto:subq=6:frameref=5"
# high, med & low will use same settings just CQ and resolution different
# This make encoding slow. Swap following if you want lower quality to also mean faster encoding speed.
#readonly MED_X264EXT_OPTS="nocabac:bframes=2:${FORCECFR}${NOBPYRAMID}threads=auto:subq=5:frameref=4"
#readonly LOW_X264EXT_OPTS="nocabac:bframes=2:${FORCECFR}${NOBPYRAMID}threads=auto:subq=4:frameref=3"
readonly MED_X264EXT_OPTS="$HIGH_X264EXT_OPTS"
readonly LOW_X264EXT_OPTS="$HIGH_X264EXT_OPTS"
# H.264 High profile level set in QLEVEL
readonly HIGH_X264HIGH_OPTS="bframes=3:${FORCECFR}${BPYRAMID}weight_b:threads=auto:direct_pred=auto:subq=6:frameref=5:partitions=all:8x8dct:mixed_refs:me=umh:trellis=1"
# high, med & low will use same settings just CQ and resolution different
# This make encoding slow. Swap following if you want lower quality to also mean faster encoding speed.
#readonly MED_X264HIGH_OPTS="bframes=3:${FORCECFR}${BPYRAMID}weight_b:threads=auto:subq=5:frameref=4:8x8dct"
#readonly LOW_X264HIGH_OPTS="bframes=3:${FORCECFR}${BPYRAMID}weight_b:threads=auto:subq=4:frameref=3"
readonly MED_X264HIGH_OPTS="$HIGH_X264HIGH_OPTS"
readonly LOW_X264HIGH_OPTS="$HIGH_X264HIGH_OPTS"
# AAC
readonly HIGH_AAC_AQUAL=100
readonly MED_AAC_AQUAL=90
readonly LOW_AAC_AQUAL=80
# OGG
readonly HIGH_OGG_AQUAL=6
readonly MED_OGG_AQUAL=5
readonly LOW_OGG_AQUAL=4
# Defaults
LAVC_OPTS=$MED_LAVC_OPTS
LAVC_CQ=$MED_LAVC_CQ
XVID_OPTS=$MED_XVID_OPTS
XVID_CQ=$MED_XVID_CQ
MP3_ABITRATE=$MED_MP3_ABITRATE
AAC_AQUAL=$MED_AAC_AQUAL
OGG_AQUAL=$MED_OGG_AQUAL
X264EXT_OPTS="level_idc=31:$MED_X264EXT_OPTS"
X264_OPTS="level_idc=31:$MED_X264HIGH_OPTS"
X264_CQ=$MED_X264_CQ
if echo "$(basename $0)" | grep -i 'mkv' >/dev/null 2>&1
then
	CONTYPE="mkv"
	QUICKTIME_MP4="NO"
elif echo "$(basename $0)" | grep -i 'mp4' >/dev/null 2>&1
then
	CONTYPE="mp4"
	QUICKTIME_MP4="NO"
elif echo "$(basename $0)" | grep -i 'mov' >/dev/null 2>&1
then
	#TODO. Not working yet don't use mov
	CONTYPE="mp4"
	QUICKTIME_MP4="YES"
elif echo "$(basename $0)" | grep -i 'avi' >/dev/null 2>&1
then
	CONTYPE="avi"
	QUICKTIME_MP4="NO"
fi
###########################################################
# ON or OFF
# debug mode
DEBUG="OFF"
DEBUGSQL="OFF"
DEBUGSG="OFF"
# Print INFO messages
INFO="ON"
# Save(via a rename) or delete nuv file. Only for transcode back into MythRecording.
SAVENUV="OFF"

[ "$DEBUGSQL" = "ON" ] && DEBUG="ON"

##### Functions ###########################################
scriptlog() {
local LEVEL="$1"
shift
local PRIORITY
local HIGHLIGHTON
local HIGHLIGHTOFF
	if [ "$LEVEL" = "BREAK" ]
	then
		echo "--------------------------------------------------------------------------------" | tee -a $LOGFILE
		return 0
	elif [ "$LEVEL" = "ERROR" ]
	then
		PRIORITY=4
		HIGHLIGHTON="${REDFG}"
		HIGHLIGHTOFF="${COLOURORIG}"
		FINALEXIT=1 # Global
	elif [ "$LEVEL" = "WARN" ]
	then
		PRIORITY=4
		HIGHLIGHTON="${REDFG}"
		HIGHLIGHTOFF="${COLOURORIG}"
	elif [ "$LEVEL" = "SUCCESS" ]
	then
		PRIORITY=5
		HIGHLIGHTON="${GREENFG}"
		HIGHLIGHTOFF="${COLOURORIG}"
	elif [ "$LEVEL" = "START" -o "$LEVEL" = "STOP" ]
	then
		PRIORITY=5
		HIGHLIGHTON="${BOLDON}"
		HIGHLIGHTOFF="${ALLOFF}"
	elif [ "$LEVEL" = "DEBUG" ]
	then
		[ "$DEBUG" = "ON" ] || return
		PRIORITY=7
		HIGHLIGHTON=""
		HIGHLIGHTOFF=""
	elif [ "$LEVEL" = "NOHEADER" ]
	then
		# Also no db logging
		echo "$*" | tee -a $LOGFILE
		return
	else
		[ "$INFO" = "ON" ] || return
		LEVEL="INFO"
		PRIORITY=6
		HIGHLIGHTON=""
		HIGHLIGHTOFF=""
	fi
	echo "${HIGHLIGHTON}$(date +%d/%m,%H:%M) [${$}] $LEVEL $*${HIGHLIGHTOFF}" | tee -a $LOGFILE

	[ "$DBLOGGING" -eq 1 ] && insertmythlogentry "$PRIORITY" "$LEVEL" "${$}" "$*"
}

versioncheck() {
local PRODUCT="$1"
local VER
local MAJ
local MIN
local PAT
	case $PRODUCT in
		mkvmerge)
			VER=$(mkvmerge -V | awk '/mkvmerge/ {print $2}')
			OLDIFS="$IFS"; IFS="."; set - $VER; IFS="$OLDIFS"
			MAJ=$(echo "$1" | tr -d '[:alpha:]'); MIN="$2"; PAT="$3"
			if [ "$VER" = "v2.5.1" ]
			then
				scriptlog INFO "mkvmerge v2.5.1. There is a known bug with this version. Workaround applied."
				MKVMERGE251BUG="YES" # Global
			elif [ "$MAJ" -lt 2 -o \( "$MAJ" -eq 2 -a "$MIN" -lt 2 \) ]
			then
				scriptlog INFO "mkvmerge $VER. This will not work with 29.97 fps video (NTSC). You need at least v2.2.0"
			fi
			scriptlog DEBUG "mkvmerge $VER"
			return 0
		;;
		convert)
			# There are several programs called convert. Check it is ImageMagick.
			convert -version 2>&1 | grep -i 'ImageMagick' >/dev/null 2>&1 && return 0 || return 1
		;;
	esac
}

chkreqs() {
local REQPROGS="$1"
local REQLIBS="$2"
local TMP
local MENCODER
	for TMP in $REQPROGS
	do
		if ! which "$TMP" >/dev/null 2>&1
		then
			scriptlog ERROR "Can't find program $TMP."
			scriptlog ERROR "$REQUIREDAPPS"
			return 1
		fi
	done
	MENCODER=$(which mencoder)
	for TMP in $REQLIBS
	do
		if ! ldd $MENCODER | grep -i  "${TMP}.*=>.*${TMP}" >/dev/null 2>&1
		then
			scriptlog ERROR "mencoder may not support $TMP."
			scriptlog ERROR "$REQUIREDAPPS"
			return 1
		fi
	done
	return 0
}

calcbitrate() {
local ASPECT=$1
local SCALE=$2
local CQ=$3
local W
local H
local BITRATE
	W=$(echo $SCALE | cut -d ':' -f1)
	H=$(echo $SCALE | cut -d ':' -f2)
	BITRATE=$(echo "((($H^2 * $ASPECT * 25 * $CQ) / 16 ) * 16) / 1000" | bc)
	echo $BITRATE
}

getsetting() {
local VALUE="$1"
local HOST=$(hostname)
local DATA
	DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select data from settings where value = "$VALUE" and hostname like "${HOST}%";
	EOF
	)
	if [ -z "$DATA" ]
	then
		DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
		select data from settings where value = "$VALUE" and (hostname is NULL or hostname = "");
	EOF
	)
	fi
	echo "$DATA"
}

# Not Used.
getstoragegroupdirs() {
	mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select distinct dirname from storagegroup;
	EOF
}

hascutlist() {
local CHANID="$1"
local STARTTIME="$2"
local DATA
	[ -n "$CHANID" ] || return 1
	DATA=$(mysql --batch --skip-column-name --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select cutlist from recorded where chanid = $CHANID and starttime = "$STARTTIME";
	EOF
	)
	[ "$DATA" -eq 1 ] && return 0 || return 1
}

getrecordfile() {
local CHANID="$1"
local STARTTIME="$2"
local DEBUGSG="$3"
local DATA
local DATALINE
local RECFILE
local SGHOST
	[ -n "$CHANID" ] || return 1
	# Storage groups
	if [ "$DEBUGSG" = "ON" ]
	then
		scriptlog INFO "CHANID $CHANID STARTTIME $STARTTIME"
		DATA=$(mysql --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
		select * from storagegroup;
		select chanid,starttime,title,subtitle,basename,storagegroup from recorded where chanid = $CHANID and starttime = "$STARTTIME";
		EOF
		)
		scriptlog INFO "Tables"
		scriptlog NOHEADER "$DATA"
	fi
	DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select a.hostname,':::',concat(a.dirname, "/", b.basename) from storagegroup a, recorded b where b.chanid = $CHANID and b.starttime = "$STARTTIME" and b.storagegroup = a.groupname;
	EOF
	)
	[ "$DEBUGSG" = "ON" ] && scriptlog INFO "Try 1 Data $DATA"
	while read DATALINE
	do
		SGHOST=$(echo "$DATALINE" | awk -F':::' '{print $1}' | sed -e 's/[ \t]*\(.*\)[ \t]*/\1/')
		RECFILE=$(echo "$DATALINE" | awk -F':::' '{print $2}' | sed -e 's/[ \t]*\(.*\)[ \t]*/\1/')
		[ "$DEBUGSG" = "ON" ] && scriptlog INFO "Try 1 Check SGHost $SGHOST RecFile $RECFILE"
		[ -f "${RECFILE}" ] && break
	done < <(echo "$DATA")
	if [ ! -f "$RECFILE" ]
	then
		# Pre Storage groups
		local RFP=$(getsetting RecordFilePrefix)
		DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
		select concat("$RFP", "/", basename) from recorded where chanid = $CHANID and starttime = "$STARTTIME" limit 1;
		EOF
		)
		[ "$DEBUGSG" = "ON" ] && scriptlog INFO "Try 2 $RFP,$DATA"
		RECFILE="$DATA"
	fi
	[ -f "$RECFILE" ] && echo "$RECFILE"
}

getsourcename() {
local CHANID="$1"
	[ -n "$CHANID" ] || return 1
	mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select b.displayname from channel a, cardinput b where a.chanid = $CHANID and a.sourceid = b.sourceid;
	EOF
}

gettitle() {
local CHANID="$1"
local STARTTIME="$2"
	[ -n "$CHANID" ] || return 1
	mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select title from recorded where chanid = $CHANID and starttime = "$STARTTIME";
	EOF
}

getsubtitle() {
local CHANID="$1"
local STARTTIME="$2"
	[ -n "$CHANID" ] || return 1
	mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select subtitle from recorded where chanid = $CHANID and starttime = "$STARTTIME";
	EOF
}

findchanidstarttime() {
local SEARCHTITLE="$1"
	mysql --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select title, subtitle, chanid, date_format(starttime, '%Y%m%d%H%i%s'), storagegroup from recorded where title like "%${SEARCHTITLE}%";
	EOF
}

updatemetadata() {
local NEW="$1"
local CHANID="$2"
local STARTTIME="$3"
local NFSIZE
	NFSIZE=$(stat -c %s "$NEW")
	NEW=$(basename "$NEW")
	mysql --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	update recorded set
	basename = "$NEW",
	filesize = $NFSIZE,
	bookmark = 0,
	editing = 0,
	cutlist = 0,
	commflagged = 0
	where chanid = $CHANID and starttime = "$STARTTIME";
	delete from recordedmarkup where chanid = $CHANID and starttime = "$STARTTIME";
	delete from recordedseek where chanid = $CHANID and starttime = "$STARTTIME";
	EOF
}

createvideocover() {
local CFDIR="$1"
local FILENAME="$2"
local ASPECT="$3"
local THDIR="${FIFODIR}/THDIR"
local THUMB_NAME=$(basename "$FILENAME" | sed -e 's/\.[am][vkp][iv4]$/\.png/')
local THUMB_PATH="${CFDIR}/${THUMB_NAME}"
local CURWD
local TH
	{
	CURWD=$(pwd)
	mkdir $THDIR && cd $THDIR || return 1
	nice -19 mplayer -really-quiet -nojoystick -nolirc -nomouseinput -ss 00:02:00 -aspect $ASPECT -ao null -frames 50 -vo png:z=5 "$FILENAME"
	TH=$(ls -1rt | tail -1)
	[ -f "$TH" ] || return
	if [ $ASPECT = "16:9" ]
	then
		convert "$TH" -resize 720x404! THWS.png
	else
		cp "$TH" THWS.png
	fi
	mv THWS.png "$THUMB_PATH"
	cd $CURWD
	rm -rf "$THDIR"
	} >/dev/null 2>&1
	echo "$THUMB_PATH"
}

getsearchtitle() {
local CHANID="$1"
local STARTTIME="$2"
local TI
local ST
local SEARCHTITLE
	[ -n "$CHANID" ] || return 1
	if [ -n "$TITLE" -a -n "$SUBTITLE" ]
	then
		SEARCHTITLE="${TITLE}:${SUBTITLE}"
	elif [ -n "$TITLE" ]
	then
		SEARCHTITLE="${TITLE}"
	fi
	echo $SEARCHTITLE
}

lookupinetref() {
# : is used to separate Title and SubTitle in SEARCHTITLE
local SEARCHTITLE="$1"
local CHANID="$2"
local STARTTIME="$3"
local IMDBCMD
local IMDBRES
local IMDBSTR=""
# INETREF will be 00000000 if not found
local INETREF=00000000
local SERIES
local EPISODE
local YEAR
local TMP
	{
        IMDBCMD=$(getsetting MovieListCommandLine)
	# This is dependent on imdb.pl and will not work with any MovieListCommandLine due to use of s=ep option.
	set - $IMDBCMD
	IMDBCMD="$1 $2"
        IMDBRES=$($IMDBCMD "$SEARCHTITLE")
        if [ -n "$IMDBRES" -a $(echo "$IMDBRES" | wc -l) -eq 1 ]
        then
		IMDBSTR="$IMDBRES"
	elif [ -n "$CHANID" ]
	then
		YEAR=$(getyear $CHANID $STARTTIME)
		if [ "$YEAR" -gt 1800 ]
		then
			for C in 0 1 -1
			do
				TMP=$(echo "$IMDBRES" | grep $(( $YEAR + $C )))
				[ -n "$TMP" -a $(echo "$TMP" | wc -l) -eq 1 ] && IMDBSTR="$TMP" && break
			done
		fi
        fi
	if [ -n "$IMDBSTR" ]
	then
                INETREF=$(echo "$IMDBSTR" | awk -F'[^0-9]' '{print $1}')
                echo $INETREF | grep '^[0-9][0-9][0-9][0-9][0-9][0-9][0-9]*$' >/dev/null 2>&1 || INETREF=00000000
	fi
        if [ "$INETREF" -eq 00000000 ]
        then
		# Try looking for episode
                OLDIFS="$IFS"; IFS=":"; set - $SEARCHTITLE; IFS="$OLDIFS"
		SERIES="$1" ; EPISODE="$2"
		if [ -n "$SERIES" -a -n "$EPISODE" ]
		then
			# option s=ep is for episode lookup
			IMDBSTR=$($IMDBCMD s=ep "$EPISODE")
			if which agrep >/dev/null 2>&1
			then
				IMDBSTR=$(echo "$IMDBSTR" | agrep -i -s -2 "$SERIES" | sort -n | head -1 | cut -d':' -f2-)
			else
				IMDBSTR=$(echo "$IMDBSTR" | grep -i "$SERIES")
			fi
			if [ $(echo "$IMDBSTR" | wc -l) -eq 1 ]
			then
				INETREF=$(echo "$IMDBSTR" | awk -F'[^0-9]' '{print $1}')
				echo $INETREF | grep '^[0-9][0-9][0-9][0-9][0-9][0-9][0-9]*$' >/dev/null 2>&1 || INETREF=00000000
			fi
		fi
        fi
	scriptlog DEBUG "inetref $INETREF"
	} >/dev/null 2>&1
        echo $INETREF
}

getseriesepisode() {
local CHANID="$1"
local STARTTIME="$2"
local INETREF="$3"
local DATA
local SE
	[ -n "$CHANID" ] || return 1

	if [ -n "$META_EPISODE" ]
	then
		SE=$(echo "$META_EPISODE" | awk "{ printf(\"${EPISODE_FORMAT}\", \$1) }")
		[ -n "$META_SEASON" ] && SE=$(echo "|$SE|$META_SEASON|" | awk -F"|" "{ printf(\"${SEASON_FORMAT}\", \$2, \$3) }")
	else
		# STARTTIME is not always the same in both tables for matching programs. ???
		DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
		select syndicatedepisodenumber from recorded a,recordedprogram b
		where a.chanid = $CHANID and a.starttime = "$STARTTIME" and a.chanid = b.chanid
		and a.title = b.title and a.subtitle = b.subtitle;
		EOF
		)
		DATA=$(echo "$DATA" | awk -F '[SE]' "/S/ { printf(\"${SEASON_FORMAT}\", sprintf(\"${EPISODE_FORMAT}\", \$2), \$3) }")
		if echo "$DATA" | egrep -q "${EPISODE_RE}"
		then
			SE="$DATA"
		elif [ $INETREF -gt 0 ]
		then
			# Lets try passing imdb page
			wget -o /dev/null -O "${FIFODIR}/${INETREF}.html" "http://www.imdb.com/title/tt${INETREF}/"
			SE=$(awk "/Season.*Episode/ {
			a=match(\$0,/Season ([0-9]+)/,s);b=match(\$0,/Episode ([0-9]+)/,e);
			if(a>0 && b>0) {
				printf(\"${SEASON_FORMAT}\", sprintf(\"${EPISODE_FORMAT}\", e[1]), s[1]);exit}
			}" "${FIFODIR}/${INETREF}.html")
		fi
	fi
	echo "$SE" | egrep "$EPISODE_RE"
}

createfiletitleSEsubtitle() {
local CHANID="$1"
local STARTTIME="$2"
local SE="$3"
local DATA
local T
local S
	FILE="$TITLE"
	[ -n "$META_ARTIST" ] && FILE="${META_ARTIST}${SEP}${FILE}"
	[ -n "$SE" ] && FILE=$(echo "|$FILE|$SE|" | awk -F"|" "{ printf(\"${TITLE_FORMAT}\", \$2, \$3 ) }")
	[ -z "$SE" -a -n "$SUBTITLE" ] && FILE="${FILE}${SEP}${SUBTITLE}"
	[ -n "$SE" -a -n "$SUBTITLE" ] && FILE="${FILE}${SUBTITLE}"
	[ -n "$META_DATE" ] && FILE=$(echo "|$FILE|$META_DATE" | awk -F"|" "{ printf(\"${DATE_FORMAT}\", \$2, \$3 ) }")
	[ -n "$TR" ] && FILE=$(echo $FILE | tr -d '[:cntrl:]' | tr -d '[:punct:]' | tr '[:space:]' "$TR")
	echo $FILE
}

is21orless() {
	local DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select subtitle from videometadata limit 1;
	EOF
	)
	echo "$DATA" | egrep 'ERROR.*Unknown column' >/dev/null 2>&1 && return 0 || return 1
}

is24ormore() {
	local DATA=$(mythtranscode --audiotrack 2>&1)
	echo "$DATA" | grep -q 'Unknown option: --audiotrack' && return 1 || return 0
}

createvideometadata() {
local FILENAME="$1"
local TITLE="$2"
local ASPECT="$3"
local CHANID="$4"
local STARTTIME="$5"
local INETREF="$6"
# SE may be null
local SE="$7"
local DIRECTOR="Unknown"
#local PLOT="None"
local PLOT="$(getplot $CHANID $STARTTIME)"
local MOVIERATING="NR"
#local YEAR=1895
local YEAR="$(getyear $CHANID $STARTTIME)"
local USERRATING=0
local RUNTIME=0
local COVERFILE="No Cover"
local GENRES=""
local COUNTRIES=""
local CATEGORY=""
local CFDIR=$(getsetting "VideoArtworkDir")
local TI
local ST
local IMDBCMD
local IMDBSTR
local GTYPE
local TH
local SE
local S
local E
local WHERE
local TMP
local IDS
local VIDID
local COUNT
	# Title name generation is a mess. Should do something better
	if ! is21orless
	then
		scriptlog INFO "MythTV V0.22 or greater. Not creating MythVideo entry. Use MythVideo menu"
		return 0
	fi
	if hasvideometadata "$FILENAME"
	then
		scriptlog INFO "$FILENAME already has a videometdata entry."
		return 0
	fi
	# Since I strip special characters in TITLE, use chanid/starttime for metadata title.
	if [ -n "$CHANID" ]
	then
		TI=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
		select title from recorded where chanid = $CHANID and starttime = "$STARTTIME";
		EOF
		)
		ST=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
		select subtitle from recorded where chanid = $CHANID and starttime = "$STARTTIME";
		EOF
		)
		if [ -n "$TI" -a -n "$SE" -a -n "$ST" ]
		then
			TITLE="\\\"${TI}\\\" ${SE} ${ST}"
		elif [ -n "$TI" -a -n "$ST" ]
		then
			TITLE="\\\"${TI}\\\" ${ST}"
		elif [ -n "$TI" ]
		then
			TITLE="${TI}"
		fi
	fi
	if [ $INETREF -gt 0 ]
	then
		IMDBCMD=$(getsetting MovieDataCommandLine)
		IMDBSTR=$($IMDBCMD $INETREF | sed -e 's/"/\\"/g')
		TMP=$(echo "$IMDBSTR" | grep '^Title' | cut -d':' -f2- | sed -e 's/^ *//')
		if [ -n "$TMP" ]
		then
			# Try and put series and episode number back in. Based on imdb placing quotes around series name. A bit dodgy
			if [ -n "$SE" ]
			then
				TMP=$(echo "$TMP" | awk -v s=${SE} '{
				r=match($0,/"(.*)" (.*)/,m)
				if(r>0) { print("\\\""m[1]"\\\" "s" "m[2]) }
				else { print($0) }
				}' | sed -e 's/\\\\"/\\"/g')
			fi
			TITLE="$TMP"
		fi
		TMP=$(echo "$IMDBSTR" | grep '^Year' | cut -d':' -f2- | sed -e 's/^ *//')
		[ -n "$TMP" ] && YEAR="$TMP"
		TMP=$(echo "$IMDBSTR" | grep '^Director' | cut -d':' -f2- | sed -e 's/^ *//')
		[ -n "$TMP" ] && DIRECTOR="$TMP"
		TMP=$(echo "$IMDBSTR" | grep '^Plot' | cut -d':' -f2- | sed -e 's/^ *//')
		[ -n "$TMP" ] && PLOT="$TMP"
		TMP=$(echo "$IMDBSTR" | grep '^UserRating' | grep -v '[<>\"]' | cut -d':' -f2- | sed -e 's/^ *//')
		[ -n "$TMP" ] && USERRATING="$TMP"
		TMP=$(echo "$IMDBSTR" | grep '^MovieRating' | cut -d':' -f2- | sed -e 's/^ *//')
		[ -n "$TMP" ] && MOVIERATING="$TMP"
		TMP=$(echo "$IMDBSTR" | grep '^Runtime' | cut -d':' -f2- | sed -e 's/^ *//')
		[ -n "$TMP" ] && RUNTIME="$TMP"
		IMDBCMD=$(getsetting MoviePosterCommandLine)
		IMDBCOVER=$($IMDBCMD $INETREF)
		if [ -n "$IMDBCOVER" ]
		then
			GTYPE=$(echo $IMDBCOVER | sed -e 's/.*\(\....\)/\1/')
			wget -o /dev/null -O "${CFDIR}/${INETREF}${GTYPE}" $IMDBCOVER
			[ -f "${CFDIR}/${INETREF}${GTYPE}" ] && COVERFILE="${CFDIR}/${INETREF}${GTYPE}"
		fi
		TMP=$(echo "$IMDBSTR" | grep '^Genres' | cut -d':' -f2- | sed -e 's/^ *//')
		[ -n "$TMP" ] && GENRES="$TMP"
		TMP=$(echo "$IMDBSTR" | grep '^Countries' | cut -d':' -f2- | sed -e 's/^ *//')
		[ -n "$TMP" ] && COUNTRIES="$TMP"
		TMP=$(echo "$IMDBSTR" | grep '^Cast' | cut -d':' -f2- | sed -e 's/^ *//')
		[ -n "$TMP" ] && CASTMEMBERS="$TMP"
	fi
	if ! [ -f "$COVERFILE" ]
	then
		scriptlog INFO "Creating cover file."
		TH=$(createvideocover "$CFDIR" "$FILENAME" $ASPECT)
		[ -f ${TH} ] && COVERFILE="${TH}"
	fi
	scriptlog INFO "Creating videometadata entry. Inetref:$INETREF. Title:$TITLE"
	if [ "$DEBUGSQL" = "ON" ]
	then
		cat <<-EOF
		insert into videometadata set
		title = "$TITLE",
		director = "$DIRECTOR",
		plot = "$PLOT",
		rating = "$MOVIERATING",
		inetref = "$INETREF",
		year = $YEAR,
		userrating = $USERRATING,
		length = $RUNTIME,
		showlevel = 1,
		filename = "$FILENAME",
		coverfile = "$COVERFILE",
		childid = -1,
		browse = 1,
		playcommand = NULL,
		category = 0;
		EOF
	fi
	mysql --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	insert into videometadata set
	title = "$TITLE",
	director = "$DIRECTOR",
	plot = "$PLOT",
	rating = "$MOVIERATING",
	inetref = "$INETREF",
	year = $YEAR,
	userrating = $USERRATING,
	length = $RUNTIME,
	showlevel = 1,
	filename = "$FILENAME",
	coverfile = "$COVERFILE",
	childid = -1,
	browse = 1,
	playcommand = NULL,
	category = 0;
	EOF
	CATEGORY=$(getcategory "$CHANID" "$STARTTIME")
	if [ -n "$GENRES" -o -n "$COUNTRIES" -o -n "$CASTMEMBERS" -o -n "$CATEGORY" ]
	then
		VIDID=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
		select intid from videometadata where filename = "$FILENAME";
		EOF
		)
	fi
	if [ -n "$VIDID" ]
	then
		if [ -n "$GENRES" ]
		then
			scriptlog DEBUG "Will check for genres $GENRES"
			OLDIFS="$IFS"; IFS=','; set - $GENRES; IFS="$OLDIFS"
			for GENRE in "$@"
			do
				ID=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
				select intid from videogenre where lcase(genre) = lcase("${GENRE}");
				EOF
				)
				if [ -z "$ID" ]
				then
					[ "$DEBUGSQL" = "ON" ] && echo "insert into videogenre set genre = ${GENRE}"
					mysql --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
					insert into videogenre set genre = "${GENRE}";
					EOF
					ID=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
					select intid from videogenre where lcase(genre) = lcase("${GENRE}");
					EOF
					)
				fi
				if [ -n "$ID" ]
				then
					TMP=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
					select idvideo from videometadatagenre where idvideo = $VIDID and idgenre = $ID;
					EOF
					)
					if [ -z "$TMP" ]
					then
						[ "$DEBUGSQL" = "ON" ] && echo "insert into videometadatagenre set idvideo = $VIDID, idgenre = $ID - $GENRE"
						mysql --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
						insert into videometadatagenre set idvideo = $VIDID, idgenre = $ID;
						EOF
						scriptlog INFO "Adding to genre $GENRE"
					fi
				fi
			done
		fi

		if [ -n "$COUNTRIES" ]
		then
			scriptlog DEBUG "Will check for countries $COUNTRIES"
			OLDIFS="$IFS"; IFS=','; set - $COUNTRIES; IFS="$OLDIFS"
			for COUNTRY in "$@"
			do
				ID=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
				select intid from videocountry where lcase(country) = lcase("${COUNTRY}");
				EOF
				)
				if [ -z "$ID" ]
				then
					[ "$DEBUGSQL" = "ON" ] && echo "insert into videocountry set country = ${COUNTRY}"
					mysql --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
					insert into videocountry set country = "${COUNTRY}";
					EOF
					ID=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
					select intid from videocountry where lcase(country) = lcase("${COUNTRY}");
					EOF
					)
				fi
				if [ -n "$ID" ]
				then
					TMP=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
					select idvideo from videometadatacountry where idvideo = $VIDID and idcountry = $ID;
					EOF
					)
					if [ -z "$TMP" ]
					then
						[ "$DEBUGSQL" = "ON" ] && echo "insert into videometadatacountry set idvideo = $VIDID, idcountry = $ID - $COUNTRY"
						mysql --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
						insert into videometadatacountry set idvideo = $VIDID, idcountry = $ID;
						EOF
						scriptlog INFO "Adding to country $COUNTRY"
					fi
				fi
			done
		fi

		if [ -n "$CASTMEMBERS" ]
		then
			scriptlog DEBUG "Will check for cast $CASTMEMBERS"
			OLDIFS="$IFS"; IFS=","; set - $CASTMEMBERS; IFS="$OLDIFS"
			for CAST in "$@"
			do
				ID=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
				select intid from videocast where lcase(cast) = lcase("${CAST}");
				EOF
				)
				if [ -z "$ID" ]
				then
					[ "$DEBUGSQL" = "ON" ] && echo "insert into videocast set cast = ${CAST}"
					mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
					insert into videocast set cast = "${CAST}";
					EOF
					ID=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
					select intid from videocast where lcase(cast) = lcase("${CAST}");
					EOF
					)
				fi
				if [ -n "$ID" ]
				then
					TMP=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
					select idvideo from videometadatacast where idvideo = $VIDID and idcast = $ID;
					EOF
					)
					if [ -z "$TMP" ]
					then
						[ "$DEBUGSQL" = "ON" ] && echo "insert into videometadatacast set idvideo = $VIDID, idcast = $ID - $CAST"
						mysql --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
						insert into videometadatacast set idvideo = $VIDID, idcast = $ID;
						EOF
						scriptlog INFO "Adding cast member $CAST"
					fi
				fi
			done
		fi

		if [ -n "$CATEGORY" ]
		then
			CATEGORY=$(echo "$CATEGORY" | tr -d ' ')
			OLDIFS="$IFS"; IFS='/'; set - $CATEGORY; IFS="$OLDIFS"
			for CAT in "$@"
			do
				# Use mappings
				[ -n "${mythcat[$CAT]}" ] && CAT=${mythcat[$CAT]}
				[ "$DEBUGSQL" = "ON" ] && echo "select intid from videocategory where lcase(category) = lcase(${CAT})"
				ID=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
				select intid from videocategory where lcase(category) = lcase("${CAT}");
				EOF
				)
				if [ -n "$ID" ]
				then
					[ "$DEBUGSQL" = "ON" ] && echo "update videometadata set category = $ID where intid = $VIDID"
					mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
					update videometadata set category = $ID where intid = $VIDID;
					EOF
					scriptlog INFO "Added to category $CAT"
					break # only 1 category
				else
					scriptlog INFO "Category $CAT does not exist"
				fi
			done
		fi
	fi
	return 0
}

hasvideometadata() {
local FILENAME="$1"
local DATA
	DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select intid from videometadata where filename = "$FILENAME";
	EOF
	)
	echo $DATA | grep '^[0-9][0-9][0-9]*$' >/dev/null 2>&1 && return 0 || return 1
}

deleterecording() {
local CHANID="$1"
local STARTTIME="$2"
	[ -n "$CHANID" ] || return 1
	mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	update recorded set recgroup = "Deleted", autoexpire = 999 where chanid = $CHANID and starttime = "$STARTTIME";
	EOF
}

insertmythlogentry() {
local PRIORITY="$1"
local LEVEL="$2"
local PID="$3"
local DETAILS="$(echo $4 | tr -d '[:cntrl:]' | tr -d '[\\\"]')"
local DATETIME=$(date '+%Y%m%d%H%M%S')
local HOST=$(hostname)
	mysql --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	insert into mythlog set
	module = "mythnuv2mkv.sh",
	priority = $PRIORITY,
	acknowledged = 0,
	logdate = $DATETIME,
	host = "$HOST",
	message = "mythnuv2mkv.sh [$PID] $LEVEL",
	details = "$DETAILS";
	EOF
}

getjobqueuecmds() {
local JOBID="$1"
local DATA
local JQCMDSTR[0]="RUN"
local JQCMDSTR[1]="PAUSE"
local JQCMDSTR[2]="RESUME"
local JQCMDSTR[4]="STOP"
local JQCMDSTR[8]="RESTART"
	DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select cmds from jobqueue where id = $JOBID;
	EOF
	)
	echo ${JQCMDSTR[$DATA]}
}

setjobqueuecmds() {
local JOBID="$1"
local CMDSSTR="$2"
local CMDS
	if echo "$CMDSSTR" | egrep '^[0-9]+$' >/dev/null 2>&1
	then
		CMDS=$CMDSSTR
	elif [ "$CMDSSTR" = "RUN" ]
	then
		CMDS=0
	fi
	if [ -n "$CMDS" ]
	then
		mysql --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
		update jobqueue set cmds = $CMDS where id = $JOBID;
		EOF
	else
		scriptlog ERROR "Invalid Job Queue Command."
	fi
}

getjobqueuestatus() {
local JOBID="$1"
local DATA
local JQSTATUSSTR[0]="UNKNOWN"
local JQSTATUSSTR[1]="QUEUED"
local JQSTATUSSTR[2]="PENDING"
local JQSTATUSSTR[3]="STARTING"
local JQSTATUSSTR[4]="RUNNING"
local JQSTATUSSTR[5]="STOPPING"
local JQSTATUSSTR[6]="PAUSED"
local JQSTATUSSTR[7]="RETRY"
local JQSTATUSSTR[8]="ERRORING"
local JQSTATUSSTR[9]="ABORTING"
local JQSTATUSSTR[256]="DONE"
local JQSTATUSSTR[272]="FINISHED"
local JQSTATUSSTR[288]="ABORTED"
local JQSTATUSSTR[304]="ERRORED"
local JQSTATUSSTR[320]="CANCELLED"
	DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select status from jobqueue where id = $JOBID;
	EOF
	)
	echo ${JQSTATUSSTR[$DATA]}
}

setjobqueuestatus() {
local JOBID="$1"
local STATUSSTR="$2"
local STATUS
	if echo "$STATUSSTR" | egrep '^[0-9]+$' >/dev/null 2>&1
	then
		STATUS=$STATUSSTR
	elif [ "$STATUSSTR" = "RUNNING" ]
	then
		STATUS=4
	elif [ "$STATUSSTR" = "PAUSED" ]
	then
		STATUS=6
	elif [ "$STATUSSTR" = "ABORTING" ]
	then
		STATUS=9
	elif [ "$STATUSSTR" = "FINISHED" ]
	then
		STATUS=272
	elif [ "$STATUSSTR" = "ERRORED" ]
	then
		STATUS=304
	fi
	if [ -n "$STATUS" ]
	then
		mysql --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
		update jobqueue set status = $STATUS where id = $JOBID;
		EOF
	else
		scriptlog ERROR "Invalid Job Queue Status."
	fi
}

getjobqueuecomment() {
local JOBID="$1"
local COMMENT="$2"
	mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select comment from jobqueue where id = $JOBID;
	EOF
}

setjobqueuecomment() {
local JOBID="$1"
local COMMENT="$2"
	mysql --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	update jobqueue set comment = "$COMMENT" where id = $JOBID;
	EOF
}

# My channelprofiles table for setting aspect at channel level.
# See http://web.aanet.com.au/auric/?q=node/1
# You probably don't have it.
getchannelaspect() {
local CHANID=$1
local DATA
	{
	DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select aspectratio from channelprofiles
		where channum = (select channum from channel where chanid = $CHANID)
		and sourceid = (select sourceid from channel where chanid = $CHANID);
	EOF
	)
	case $DATA in
		16:9|4:3) true ;;
		'') DATA=$DEFAULTMPEG2ASPECT ;;
		*) DATA=NA ;;
	esac
	} >/dev/null 2>&1
	echo $DATA
}

# aspect ratio of the V4L or MPEG capture card associated with CHANID
# No good for any other type of card. e.g. DVB.
querycardaspect() {
local CHANID=$1
local DATA
	DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select value from codecparams where name = 'mpeg2aspectratio'
	and profile = (select id from recordingprofiles where name = 'default'
		and profilegroup = (select id from profilegroups
			where cardtype = (select cardtype from capturecard
				where cardid = (select cardid from cardinput
					where sourceid = (select sourceid from channel
						where chanid = $CHANID)
					)
				)
			)
		);
	EOF
	)
	[ "$DATA" != "4:3" -a "$DATA" != "16:9" ] && DATA="NA"
	echo $DATA
}

getaviinfomidentify() {
local FILE="$1"
local ATRACK="$2"
shift 2
local PROPS="$@"
local MPOP
local TMP
local p
local RES
local ASPECTFOUNDIN
local width=1			; infokey[1]="ID_VIDEO_WIDTH"
local height=2			; infokey[2]="ID_VIDEO_HEIGHT"
local fps=3			; infokey[3]="ID_VIDEO_FPS"
local audio_sample_rate=4	; infokey[4]="ID_AUDIO_RATE"
local audio_channels=5		; infokey[5]="ID_AUDIO_NCH"
local aspect=6			; infokey[6]="ID_VIDEO_ASPECT"
local length=7			; infokey[7]="ID_LENGTH"
local video_format=8		; infokey[8]="ID_VIDEO_FORMAT"
local audio_format=9		; infokey[9]="ID_AUDIO_CODEC"
	ATRACK_PID=$(mplayer -really-quiet -nojoystick -nolirc -nomouseinput -vo null -ao null -frames 0 -identify "$FILE" 2>/dev/null | \
		awk -F"=" "/ID_AUDIO_ID=([0-9]+)/ { if ( x++ == $ATRACK ) print \$2 }")
	MPOP=$(mplayer -aid ${ATRACK_PID} -really-quiet -nojoystick -nolirc -nomouseinput -vo null -ao null -frames 0 -identify "$FILE" 2>/dev/null)
	for p in $PROPS
	do
		[ -n "${infokey[$p]}" ] && p=${infokey[$p]}
		case $p in
			"scan_type")
				TMP="NA"
			;;
			"finfo")
				TMP="NA"
			;;
			"audio_bitrate")
				TMP="NA"
			;;
			"audio_resolution")
				TMP="NA"
			;;
			"audio_language")
				TMP="NA"
			;;
			"ID_VIDEO_ASPECT")
				TMP="$(echo "$MPOP" | awk -F'=' '/ID_VIDEO_ASPECT/ {if($2>1.1 && $2<1.5)print "4:3";if($2>1.6 && $2<2)print "16:9"}')"
				[ "$TMP" != "4:3" -a "$TMP" != "16:9" ] && TMP="NA"
				ASPECTFOUNDIN="File"
				if [ "$TMP" = "NA" -a ${FILE##*.} = "mpg" -a -n "$CHANID" ]
				then
					TMP=$(getchannelaspect $CHANID)
					ASPECTFOUNDIN="Channel"
				fi
				if [ "$TMP" = "NA" -a ${FILE##*.} = "mpg" -a -n "$CHANID" ]
				then
					TMP=$(querycardaspect $CHANID)
					ASPECTFOUNDIN="Card"
				fi
				if [ "$TMP" = "NA" -a ${FILE##*.} = "mpg" ]
				then
					TMP=$DEFAULTMPEG2ASPECT
					ASPECTFOUNDIN="Default"
				fi
				TMP="$TMP,$ASPECTFOUNDIN"
			;;
			"ID_VIDEO_HEIGHT")
				TMP="$(echo "$MPOP" | grep $p | tail -1 | cut -d'=' -f2)"
				[ "$TMP" = "1080" ] && TMP="1088" # HD FIX
			;;
			"ID_VIDEO_FORMAT")
				TMP="$(echo "$MPOP" | grep $p | tail -1 | cut -d'=' -f2)"
				case "$TMP" in
					"0x10000002") TMP="MPEG" ;;
					"avc1") TMP="AVC" ;;
					"MPEG-4 Visual") TMP="MPEG4" ;;
					"FMP4") TMP="MPEG4" ;;
					"DX50") TMP="DIVX" ;;
					"H264") TMP="H264" ;;
				esac
			;;
			*)
				TMP="$(echo "$MPOP" | grep $p | tail -1 | cut -d'=' -f2)"
			;;
		esac
		[ -z "$RES" ] && RES="$TMP" || RES="${RES}:${TMP}"
	done
	echo "$RES"
}

getaviinfomediainfo() {
local FILE="$1"
local ATRACK="$2"
shift
local PROPS="$@"
local TMP
local p
local RES
local ASPECTFOUNDIN
	for p in $PROPS
	do
		TMP=""
		case "$p" in
			"aspect")
				TMP=$(mediainfo --Inform="Video;%DisplayAspectRatio/String%" "$FILE")
				if [ "$TMP" = "4:3" -o "$TMP" = "4/3" ]
				then
					ASPECTFOUNDIN="File"
				elif [ "$TMP" = "16:9" -o "$TMP" = "16/9" ]
				then
					ASPECTFOUNDIN="File"
				else
					TMP="NA"
				fi

				if [ "$TMP" = "NA" -a ${FILE##*.} = "mpg" -a -n "$CHANID" ]
				then
					TMP=$(getchannelaspect $CHANID)
					ASPECTFOUNDIN="Channel"
				fi
				if [ "$TMP" = "NA" -a ${FILE##*.} = "mpg" -a -n "$CHANID" ]
				then
					TMP=$(querycardaspect $CHANID)
					ASPECTFOUNDIN="Card"
				fi
				if [ "$TMP" = "NA" -a ${FILE##*.} = "mpg" ]
				then
					TMP=$DEFAULTMPEG2ASPECT
					ASPECTFOUNDIN="Default"
				fi
				[ -z "$TMP" ] && TMP=$(getaviinfomidentify "$FILE" $ATRACK "$p")
				TMP="$TMP,$ASPECTFOUNDIN"
			;;
			"height")
				TMP=$(mediainfo --Inform="Video;%Height%" "$FILE")
				[ -z "$TMP" ] && TMP=$(getaviinfomidentify "$FILE" $ATRACK "$p")
				[ "$TMP" = "1080" ] && TMP="1088" # HD FIX
			;;
			"audio_sample_rate")
				TMP=$(mediainfo --Inform="Audio;%SamplingRate/String%\n" "$FILE" | awk "{ if ( x++ == $ATRACK ) print \$1 * 1000 }")
				[ -z "$TMP" ] && TMP=$(getaviinfomidentify "$FILE" $ATRACK "$p")
			;;
			"Duration")
				TMP=$(mediainfo --Inform="Video;%Duration%" "$FILE")
			;;
			"video_format")
				TMP=$(getaviinfomidentify "$FILE" video_format)
				[ -z "$TMP" ] && TMP=$(getaviinfomidentify "$FILE" $ATRACK "$p")
			;;
			"width")
				TMP=$(mediainfo --Inform="Video;%Width%" "$FILE")
				[ -z "$TMP" ] && TMP=$(getaviinfomidentify "$FILE" $ATRACK "$p")
			;;
			"fps")
				TMP=$(mediainfo --Inform="Video;%FrameRate%" "$FILE")
				[ -z "$TMP" ] && TMP=$(getaviinfomidentify "$FILE" $ATRACK "$p")
			;;
			"audio_channels")
				TMP=$(mediainfo --Inform="Audio;%Channel(s)/String%\n" "$FILE" | awk "{ if ( x++ == $ATRACK ) print \$1 }")
				[ -z "$TMP" ] && TMP=$(getaviinfomidentify "$FILE" $ATRACK "$p")
			;;
			"audio_bitrate")
				TMP=$(mediainfo --Inform="Audio;%BitRate/String%\n" "$FILE" | awk "{ if ( x++ == $ATRACK ) print \$1 }")
				[ -z "$TMP" ] && TMP="NA"
			;;
			"audio_resolution")
				TMP=$(mediainfo --Inform="Audio;%Resolution/String%\n" "$FILE" | awk "{ if ( x++ == $ATRACK ) print \$1 }")
				[ -z "$TMP" ] && TMP="NA"
			;;
			"scan_type")
				TMP=$(mediainfo --Inform="Video;%ScanType%" "$FILE")
				[ "$TMP" = "MBAFF" ] && TMP="Interlaced"
				[ -z "$TMP" ] && TMP="NA"
			;;
			"audio_language")
				TMP=$(mediainfo --Inform="Audio;%Language/String3%\n" "$FILE" | awk "{ if ( x++ == $ATRACK ) print \$1 }")
				[ -z "$TMP" ] && TMP="NA"
			;;
			"audio_format")
				TMP=$(mediainfo --Inform="Audio;%Format%\n" "$FILE" | awk "{ if ( x++ == $ATRACK ) print \$1 }")
				[ -z "$TMP" ] && TMP="NA"
			;;
		esac
		[ -z "$RES" ] && RES="$TMP" || RES="${RES}:${TMP}"
	done
	echo "$RES"
}

getnuvinfo() {
export NUVINFOFILE="$1"
shift
export NUVINFOPROPS="$@"
	PROPS=$(sed -n '/^#STARTNUVINFO$/,/#ENDNUVINFO/p' $CMD | perl)
	echo "$PROPS"
}

getvidinfo() {
local FILE="$1"
local ATRACK="$2"
shift 2
local PROPS="$@"
local RES
	if echo "$FILE" | grep '\.nuv' >/dev/null 2>&1
	then
		RES=$(getnuvinfo "$FILE" $PROPS)
	else
		if [ "$USEMEDIAINFO" = "TRUE" ] && which mediainfo >/dev/null 2>&1
		then
			RES=$(getaviinfomediainfo "$FILE" $ATRACK $PROPS)
		else
			RES=$(getaviinfomidentify "$FILE" $ATRACK $PROPS)
		fi
	fi
	echo "$RES"
}

getaspect() {
local FILE="$1"
local ASPECT="NA"
	ASPECT=$(getvidinfo "$FILE" 0 aspect)
	ASPECT=$(echo $ASPECT | sed -e 's/\./:/')
	echo "$ASPECT" | grep ',' >/dev/null 2>&1 || ASPECT="$ASPECT,File"
	echo "$ASPECT"
}

getlengthffmpeg() {
FILE="$1"
local LENGTH=""
	LENGTH=$(ffmpeg -i "$FILE" 2>&1 | awk -F'[:.]' '/Duration: / {print $2 * 3600 + $3 * 60 + $4}')
	echo "$LENGTH" | grep '^[0-9][0-9]*$'
}

getlength() {
FILE="$1"
local LENGTH=""
	LENGTH=$(getaviinfomidentify "$FILE" 0 length)
	if [ -z "$LENGTH" -o "$LENGTH" -lt 1 ]
	then
		scriptlog DEBUG "getaviinfomidentify failed length $LENGTH"
		LENGTH=$(getlengthffmpeg "$FILE")
		if [ -z "$LENGTH" -a "$LENGTH" -lt 0 ]
		then
			scriptlog DEBUG "getlengthffmpeg failed length $LENGTH"
			return 1
		fi
	fi
	echo $LENGTH
}

# save value $2 in variable $1, optionally saving the original value into \$SAVED$1
setsave() {
	local VARNAME=$1
	local SAVED="SAVED${VARNAME}"
	local VALUE=$2
	local SAVE=$3
	scriptlog DEBUG SetSaving "$VARNAME=$VALUE (old: ${!VARNAME}, save: $SAVE)"
	# only save once, and only if changed
	[ -n "$SAVE" -a -z "${!SAVED}" -a "${!VARNAME}" != "$VALUE" ] && eval "$SAVED=\"${!VARNAME}\""
	# forget old saved value
	[ -z "$SAVE" ] && eval "$SAVED="
	eval "${VARNAME}=\"${VALUE}\""
}

# recall saved value of variable $1, if available
recall() {
	if [ -z "$@" ]
	then
		for VARNAME in $RECALL
		do
			recall $VARNAME
		done
		for VARNAME in $CLEAN
		do
			eval "$VARNAME="
		done
	else
		local VARNAME=$1
		local SAVED="SAVED${VARNAME}"
		if [ -n "${!SAVED}" ]
		then
			scriptlog DEBUG "Recalling $VARNAME from ${!VARNAME}, saved ${!SAVED}"
			eval "${VARNAME}=\"${!SAVED}\""
			eval "${SAVED}="
		fi
	fi
}

setaspect() {
	setsave ASPECTINLINE "$1" "$2"
}

setdenoise() {
	setsave DENOISE "$(echo $1 | tr '[a-z]' '[A-Z]')" "$2"
	if echo "$DENOISE" | egrep -i 'ON|YES' >/dev/null 2>&1
	then
		setsave POSTVIDFILTERS "${POSTVIDFILTERS}${DENOISEFILTER}," "$2"
		scriptlog INFO "Denoise filter added."
	else
		setsave POSTVIDFILTERS "$(echo ${POSTVIDFILTERS} | sed -e 's/'${DENOISEFILTER}',//')" "$2"
		scriptlog INFO "Denoise filter removed."
	fi
}

setdeblock() {
	setsave DEBLOCK "$(echo $1 | tr '[a-z]' '[A-Z]')" "$2"
	if echo "$DEBLOCK" | egrep -i 'ON|YES' >/dev/null 2>&1
	then
		setsave POSTVIDFILTERS "${POSTVIDFILTERS}${DEBLOCKFILTER}," "$2"
		scriptlog INFO "Deblock filter added."
	else
		setsave POSTVIDFILTERS "$(echo ${POSTVIDFILTERS} | sed -e 's/'${DEBLOCKFILTER}',//')" "$2"
		scriptlog INFO "Deblock filter removed."
	fi
}

setdeinterlace() {
	setsave DEINTERLACE "$(echo $1 | tr '[a-z]' '[A-Z]')" "$2"
	if echo "$DEINTERLACE" | egrep -i 'ON|YES' >/dev/null 2>&1
	then
		scriptlog INFO "Deinterlace filter made available."
	else
		scriptlog INFO "Deinterlace filter made unavailable."
	fi
}

setinvtelecine() {
	setsave INVTELECINE "$(echo "$1" | tr '[a-z]' '[A-Z]')" "$2"
	if echo "$INVTELECINE" | egrep -i 'ON|YES' >/dev/null 2>&1
	then
		scriptlog INFO "Invtelecine filter made available."
	else
		scriptlog INFO "Invtelecine filter made unavailable."
	fi
}

setcrop() {
	setsave CROP $(echo "$1" | tr '[a-z]' '[A-Z]') "$2"
	if echo "$CROP" | egrep '[0-9]+' >/dev/null 2>&1
	then
		setsave CROPSIZE "$CROP" "$2"
		setsave CROP "ON" "$2"
		scriptlog INFO "Cropping $CROPSIZE pixels from each side"
		[ $(( ($CROPSIZE*2) % 16 )) -ne 0 ] && scriptlog WARN "WARNING Crop sizes NOT a multiple of 16. This is bad"
	elif [ "$CROP" = "ON" ]
	then
		scriptlog INFO "Cropping $CROPSIZE pixels from each side"
	else
		scriptlog INFO "Crop set $CROP."
	fi
}

setdeleterec() {
	setsave DELETEREC "$(echo "$1" | tr '[a-z]' '[A-Z]')" "$2"
	scriptlog INFO "Delete Recording set to $DELETEREC."
}

setchapterduration() {
	setsave CHAPTERDURATION "$1" "$2"
	scriptlog INFO "Chapter Duration set to $CHAPTERDURATION."
}

setchapterfile() {
	setsave CHAPTERFILE "$1" "$2"
	if [ -f "$CHAPTERFILE" ]
	then
		scriptlog INFO "Chapter File set to $CHAPTERFILE."
	else
		setsave CHAPTERFILE "" "$2"
		scriptlog ERROR "Chapter File $CHAPTERFILE not found."
	fi
}

setcopydir() {
	setsave COPYDIR "$1" "$2"
	if [ ! -d "$COPYDIR" -o ! -w "$COPYDIR" ] && ! mkdir -p "$COPYDIR"
	then
		scriptlog ERROR "$COPYDIR does not exist and cannot be created or is not writable. Continuing but result will be left in source directory unless $COPYDIR is created before job completes."
		return 1
	else
		scriptlog INFO "Video will be located in $COPYDIR."
		return 0
	fi
}

setcontype() {
	local TMP=$(echo "$1" | tr '[A-Z]' '[a-z]')
	local SAVE=$2
	local OLDIFS="$IFS"; IFS=","; set - $TMP; IFS="$OLDIFS"
	local TMP1="$1" ; local TMP2="$2"
	if [ "$TMP1" = "mp4" ]
	then
		if [ -n "$CHANID" -a -z "$COPYDIR" ]
		then
			setsave CONTYPE "avi" "$SAVE"
			setsave QUICKTIME_MP4 "NO" "$SAVE"
			scriptlog ERROR "Changed to $TMP1 failed. mp4 not supported in MythRecord."
		elif ! chkreqs "$MP4REQPROGS" "$MP4REQLIBS"
		then
			scriptlog ERROR "Changed to $TMP1 failed. Missing Requirements."
			exit $FINALEXIT
		else
			setsave CONTYPE "mp4" "$SAVE"
			setsave QUICKTIME_MP4 "NO" "$SAVE"
			scriptlog INFO "Changed to $CONTYPE."
		fi
	elif [ "$TMP1" = "mov" ]
	then
		if [ -n "$CHANID" -a -z "$COPYDIR" ]
		then
			setsave CONTYPE "avi" "$SAVE"
			setsave QUICKTIME_MP4 "NO" "$SAVE"
			scriptlog ERROR "Changed to $TMP1 failed. mov not supported in MythRecord."
		elif ! chkreqs "$MP4REQPROGS" "$MP4REQLIBS"
		then
			scriptlog ERROR "Changed to $TMP1 failed. Missing Requirements."
			exit $FINALEXIT
		else
			setsave CONTYPE "mp4" "$SAVE"
			setsave QUICKTIME_MP4 "YES" "$SAVE"
			scriptlog INFO "Changed to $CONTYPE (mov)."
		fi
	elif [ "$TMP1" = "mkv" ]
	then
		if [ -n "$CHANID" -a -z "$COPYDIR" ]
		then
			setsave CONTYPE "avi" "$SAVE"
			setsave QUICKTIME_MP4 "NO" "$SAVE"
			scriptlog ERROR "Changed to $TMP1 failed. mkv not supported in MythRecord."
		elif ! chkreqs "$MKVREQPROGS" "$MKVREQLIBS"
		then
			scriptlog ERROR "Changed to $TMP1 failed. Missing Requirements."
			exit $FINALEXIT
		else
			setsave CONTYPE "mkv" "$SAVE"
			setsave QUICKTIME_MP4 "NO" "$SAVE"
			[ "$TMP2" = "ogg" ] && setsave MKVAUD "ogg" "$SAVE"
			[ "$TMP2" = "acc" ] && setsave MKVAUD "acc" "$SAVE"
			scriptlog INFO "Changed to ${CONTYPE},${MKVAUD}."
		fi
	elif [ "$TMP1" = "avi" ]
	then
		if ! chkreqs "$AVIREQPROGS" "$AVIREQLIBS"
		then
			scriptlog ERROR "Changed to $TMP1 failed. Missing Requirements."
			exit $FINALEXIT
		else
			setsave CONTYPE "avi" "$SAVE"
			setsave QUICKTIME_MP4 "NO" "$SAVE"
			[ "$TMP2" = "xvid" ] && setsave AVIVID "xvid" "$SAVE"
			[ "$TMP2" = "lavc" ] && setsave AVIVID "lavc" "$SAVE"
			[ "$TMP2" = "divx" ] && setsave AVIVID "lavc" "$SAVE"
			scriptlog INFO "Changed to ${CONTYPE},${AVIVID}."
		fi
	else
		scriptlog ERROR "Changed to $TMP1 failed. Invalid contype."
	fi
}

setpass() {
	TMP=$(echo "$1" | tr '[A-Z]' '[a-z]')
	if [ "$TMP" = "one" -o "$TMP" = "1" ]
	then
		scriptlog INFO "Changed to $TMP pass."
		setsave PASS "one" "$2"
	elif [ "$TMP" = "two" -o "$TMP" = "2" ]
	then
		scriptlog INFO "Changed to $TMP pass."
		setsave PASS "two" "$2"
	else
		scriptlog ERROR "Changed to $TMP failed. Invalid value for pass."
	fi
}

setquality() {
	QLEVEL=$1
	SAVE=$2
	if echo "$QLEVEL" | grep -i "high" >/dev/null 2>&1
	then
		setsave SCALE43 $HIGH_SCALE43 "$SAVE"
		setsave SCALE169 $HIGH_SCALE169 "$SAVE"
		setsave LAVC_CQ $HIGH_LAVC_CQ "$SAVE"
		setsave LAVC_OPTS $HIGH_LAVC_OPTS "$SAVE"
		setsave XVID_CQ $HIGH_XVID_CQ "$SAVE"
		setsave XVID_OPTS $HIGH_XVID_OPTS "$SAVE"
		setsave MP3_ABITRATE $HIGH_MP3_ABITRATE "$SAVE"
		setsave X264_CQ $HIGH_X264_CQ "$SAVE"
		setsave X264EXT_OPTS "level_idc=31:$HIGH_X264EXT_OPTS" "$SAVE"
		setsave X264_OPTS "level_idc=31:$HIGH_X264HIGH_OPTS" "$SAVE"
		setsave AAC_AQUAL $HIGH_AAC_AQUAL "$SAVE"
		setsave OGG_AQUAL $HIGH_OGG_AQUAL "$SAVE"
	elif echo "$QLEVEL" | grep -i "med" >/dev/null 2>&1
	then
		setsave SCALE43 $MED_SCALE43 "$SAVE"
		setsave SCALE169 $MED_SCALE169 "$SAVE"
		setsave LAVC_CQ $MED_LAVC_CQ "$SAVE"
		setsave LAVC_OPTS $MED_LAVC_OPTS "$SAVE"
		setsave XVID_CQ $MED_XVID_CQ "$SAVE"
		setsave XVID_OPTS $MED_XVID_OPTS "$SAVE"
		setsave MP3_ABITRATE $MED_MP3_ABITRATE "$SAVE"
		setsave X264_CQ $MED_X264_CQ "$SAVE"
		setsave X264EXT_OPTS "level_idc=31:$MED_X264EXT_OPTS" "$SAVE"
		setsave X264_OPTS "level_idc=31:$MED_X264HIGH_OPTS" "$SAVE"
		setsave AAC_AQUAL $MED_AAC_AQUAL "$SAVE"
		setsave OGG_AQUAL $MED_OGG_AQUAL "$SAVE"
	elif echo "$QLEVEL" | grep -i "low" >/dev/null 2>&1
	then
		setsave SCALE43 $LOW_SCALE43 "$SAVE"
		setsave SCALE169 $LOW_SCALE169 "$SAVE"
		setsave LAVC_CQ $LOW_LAVC_CQ "$SAVE"
		setsave LAVC_OPTS $LOW_LAVC_OPTS "$SAVE"
		setsave XVID_CQ $LOW_XVID_CQ "$SAVE"
		setsave XVID_OPTS $LOW_XVID_OPTS "$SAVE"
		setsave MP3_ABITRATE $LOW_MP3_ABITRATE "$SAVE"
		setsave X264_CQ $LOW_X264_CQ "$SAVE"
		setsave X264EXT_OPTS "level_idc=30:$LOW_X264EXT_OPTS" "$SAVE"
		setsave X264_OPTS "level_idc=30:$LOW_X264HIGH_OPTS" "$SAVE"
		setsave AAC_AQUAL $LOW_AAC_AQUAL "$SAVE"
		setsave OGG_AQUAL $LOW_OGG_AQUAL "$SAVE"
	elif echo "$QLEVEL" | egrep -i "480" >/dev/null 2>&1
	then
		# 480 scale, high everything else
		setsave SCALE43 $FE_SCALE43 "$SAVE"
		setsave SCALE169 $FE_SCALE169 "$SAVE"
		setsave LAVC_CQ $HIGH_LAVC_CQ "$SAVE"
		setsave LAVC_OPTS $HIGH_LAVC_OPTS "$SAVE"
		setsave XVID_CQ $HIGH_XVID_CQ "$SAVE"
		setsave XVID_OPTS $HIGH_XVID_OPTS "$SAVE"
		setsave MP3_ABITRATE $HIGH_MP3_ABITRATE "$SAVE"
		setsave X264_CQ $HIGH_X264_CQ "$SAVE"
		setsave X264EXT_OPTS "level_idc=31:$HIGH_X264EXT_OPTS" "$SAVE"
		setsave X264_OPTS "level_idc=31:$HIGH_X264HIGH_OPTS" "$SAVE"
		setsave AAC_AQUAL $HIGH_AAC_AQUAL "$SAVE"
		setsave OGG_AQUAL $HIGH_OGG_AQUAL "$SAVE"
	elif echo "$QLEVEL" | egrep -i "576" >/dev/null 2>&1
	then
		# 576 scale, high everything else
		setsave SCALE43 $FS_SCALE43 "$SAVE"
		setsave SCALE169 $FS_SCALE169 "$SAVE"
		setsave LAVC_CQ $HIGH_LAVC_CQ "$SAVE"
		setsave LAVC_OPTS $HIGH_LAVC_OPTS "$SAVE"
		setsave XVID_CQ $HIGH_XVID_CQ "$SAVE"
		setsave XVID_OPTS $HIGH_XVID_OPTS "$SAVE"
		setsave MP3_ABITRATE $HIGH_MP3_ABITRATE "$SAVE"
		setsave X264_CQ $HIGH_X264_CQ "$SAVE"
		setsave X264EXT_OPTS "level_idc=31:$HIGH_X264EXT_OPTS" "$SAVE"
		setsave X264_OPTS "level_idc=31:$HIGH_X264HIGH_OPTS" "$SAVE"
		setsave AAC_AQUAL $HIGH_AAC_AQUAL "$SAVE"
		setsave OGG_AQUAL $HIGH_OGG_AQUAL "$SAVE"
	elif echo "$QLEVEL" | egrep -i "720" >/dev/null 2>&1
	then
		# 720 scale, high everything else
		setsave SCALE43 $ST_SCALE43 "$SAVE"
		setsave SCALE169 $ST_SCALE169 "$SAVE"
		setsave LAVC_CQ $HIGH_LAVC_CQ "$SAVE"
		setsave LAVC_OPTS $HIGH_LAVC_OPTS "$SAVE"
		setsave XVID_CQ $HIGH_XVID_CQ "$SAVE"
		setsave XVID_OPTS $HIGH_XVID_OPTS "$SAVE"
		setsave MP3_ABITRATE $HIGH_MP3_ABITRATE "$SAVE"
		setsave X264_CQ $HIGH_X264_CQ "$SAVE"
		setsave X264EXT_OPTS "level_idc=41:$HIGH_X264EXT_OPTS" "$SAVE"
		setsave X264_OPTS "level_idc=41:$HIGH_X264HIGH_OPTS" "$SAVE"
		setsave AAC_AQUAL $HIGH_AAC_AQUAL "$SAVE"
		setsave OGG_AQUAL $HIGH_OGG_AQUAL "$SAVE"
	elif echo "$QLEVEL" | grep -i "1080" >/dev/null 2>&1
	then
		# 1080 scale, high everything else
		setsave SCALE43 $TE_SCALE43 "$SAVE"
		setsave SCALE169 $TE_SCALE169 "$SAVE"
		setsave LAVC_CQ $HIGH_LAVC_CQ "$SAVE"
		setsave LAVC_OPTS $HIGH_LAVC_OPTS "$SAVE"
		setsave XVID_CQ $HIGH_XVID_CQ "$SAVE"
		setsave XVID_OPTS $HIGH_XVID_OPTS "$SAVE"
		setsave MP3_ABITRATE $HIGH_MP3_ABITRATE "$SAVE"
		setsave X264_CQ $HIGH_X264_CQ "$SAVE"
		setsave X264EXT_OPTS "level_idc=42:$HIGH_X264EXT_OPTS" "$SAVE"
		setsave X264_OPTS "level_idc=42:$HIGH_X264HIGH_OPTS" "$SAVE"
		setsave AAC_AQUAL $HIGH_AAC_AQUAL "$SAVE"
		setsave OGG_AQUAL $HIGH_OGG_AQUAL "$SAVE"
	fi
	scriptlog INFO "Changed to $QLEVEL quality."
}

setaudiotracks() {
	local TMP=$1
	local SAVE=$2
	if [[ $TMP =~ ^([0-9]+(:[a-z]{3})?(,|$))+$ ]]
	then
		if echo $TMP | egrep -q "[1-9]" && ! is24ormore
		then
			scriptlog ERROR "Audio track selection is only supported on MythTV >= 0.24"
			TMP=$(echo $TMP | sed "s/[1-9]/0/g")
		fi
		if [ $CONTYPE != "mkv" -a $CONTYPE != "mp4" ]
		then
			if echo $TMP | grep -q ","
			then
				scriptlog ERROR "Multiple audio tracks are only supported in mkv and mp4"
				setsave ATRACKS "${TMP/,*/}" "$SAVE"
			fi
		else
			setsave ATRACKS "$TMP" "$SAVE"
		fi
	else
		scriptlog ERROR "Cannot parse audio tracks info"
		setsave ATRACKS 0 "$SAVE"
	fi
	scriptlog DEBUG "Audio track definitions: $ATRACKS"
}

parsetitle() {
	local DATA=$@
	while [[ ${DATA} =~ ([a-z]+)\|([^|]*)($| ) ]]; do
		M=${BASH_REMATCH[0]}
		[ -n "${DATA%%$M*}" ] && setsave SUBTITLE "${DATA%% $M*}" "true"
		DATA=${DATA#*$M}
		T=${BASH_REMATCH[1]}
		D=${BASH_REMATCH[2]}
		case $T in
			[tT]) setsave TITLE "$D" "true" ;;
			[sS]) setsave SUBTITLE "$D" "true" ;;
			[nN]) setsave META_SEASON "$D" "true" ;;
			[eE]) setsave META_EPISODE "$D" "true" ;;
			[aA]) setsave META_ARTIST "$D" "true" ;;
			[rR]) setsave META_DIRECTOR "$D" "true" ;;
			[bB]) setsave META_ALBUM "$D" "true" ;;
			[cC]) setsave META_COMMENT "$D" "true" ;;
			[lL]) setsave META_LOCATION "$D" "true" ;;
			[yYdD]) if [[ $D =~ ^[0-9]{4}$ ]]; then
				date=$D
			      elif [[ $D =~ ^([0-9]{4})[^0-9]([0-9]{2})[^0-9]([0-9]{2})$ ]]; then
				date=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}
			      elif [[ $D =~ ^([0-9]{2})[^0-9]([0-9]{2})[^0-9]([0-9]{4})$ ]]; then
				date=${BASH_REMATCH[3]}.${BASH_REMATCH[2]}.${BASH_REMATCH[1]}
			      else
				scriptlog ERROR "Wrong date: $D"
				continue
			      fi
			      setsave META_DATE "$date" "true"
			      ;;
			[qQ]) setquality "$D" "true" ;;
			[fF]) setcontype "$D" "true" ;;
			"aud") setaudiotracks "$D" "true" ;;
			"asp") setaspect "$D" "true" ;;
			"den") setdenoise "$D" "true" ;;
			"deb") setdeblock "$D" "true" ;;
			"dei") setdeinterlace "$D" "true" ;;
			"inv") setinvtelecine "$D" "true" ;;
			"crop") setcrop "$D" "true" ;;
			"del") setdeleterec "$D" "true" ;;
			"chap") setchapterduration "$D" "true" ;;
			"chapf") setchapterfile "$D" "true" ;;
			"dir") [ "${D:0:1}" == "/" ] && setcopydir "$D" "true" || setcopydir "$COPYDIR/$D" "true" ;;
			"pass") setpass "$D" "true" ;;
			*) scriptlog ERROR "Unknown tag: $T|$D" ;;
		esac
	done
}

stoptime() {
local STARTSECS=$1
local MAXRUNHOURS=$2
local CURSECS
local ENDSECS
	[ "$MAXRUNHOURS" = "NA" ] && return 1
	CURSECS=$(date +%s)
	ENDSECS=$(( $STARTSECS + ( $MAXRUNHOURS * 60 * 60 ) ))
	[ "$ENDSECS" -gt "$CURSECS" ] && return 1 || return 0
}

checkoutput() {
local INPUT="$1"
local OUTPUT="$2"
local MENCODERRES="$3"
local OUTPUTCHECKS="$4"
local VIDFOR
local OUTSIZE
local INSIZE
local RAT
local SCANOUTFILE
local LCOUNT
local ECOUNT
local INFRAMES
local OUTFRAMES
local DIFF
	if echo "$OUTPUTCHECKS" | grep -v "NOSIZE" >/dev/null 2>&1
	then
		scriptlog INFO "Checking output size."
		OUTSIZE=$(stat -c %s "$OUTPUT" 2>/dev/null || echo 0)
		if [ "$OUTSIZE" -eq 0 ]
		then
			scriptlog ERROR "$OUTPUT zero length."
			scriptlog INFO "This check can be disabled with --outputchecks=NOSIZE"
			return 1
		fi
	fi

	if echo "$OUTPUTCHECKS" | grep -v "NOVIDINFO" >/dev/null 2>&1
	then
		scriptlog INFO "Checking output video info."
		VIDFOR=$(getvidinfo "$OUTPUT" video_format)
		case $VIDFOR in
			MPEG4|AVC|XVID|DIVX|H264)
				true
			;;
			*)
				scriptlog ERROR "$OUTPUT ($VIDFOR) does not look like correct avi/mp4/mkv file."
				scriptlog INFO "This check can be disabled with --outputchecks=NOVIDINFO"
				return 1
			;;
		esac
	fi

	if ! hascutlist $CHANID $STARTTIME && echo "$OUTPUTCHECKS" | grep -v "NOSIZERATIO" >/dev/null 2>&1
	then
		scriptlog INFO "Checking input/output size ratio."
		INSIZE=$(stat -c %s "$INPUT" 2>/dev/null || echo 0)
		RAT=$(( $INSIZE / $OUTSIZE ))
		if [ "$RAT" -gt 16 ]
		then
			scriptlog ERROR "ratio of $RAT between $INPUT and $OUTPUT sizes greater than 16."
			scriptlog INFO "This check can be disabled with --outputchecks=NOSIZERATIO"
			return 1
		fi
	fi

	if echo "$OUTPUTCHECKS" | grep -v "NOFRAMECOUNT" >/dev/null 2>&1 && [ -f "$MENCODERRES" ]
	then
		scriptlog INFO "Checking input/output frame count."
		INFRAMES=$(tail -40 "$MENCODERRES" | awk '/Video stream:/ {F=$12} END {print F}')
		OUTFRAMES=$(nice mencoder -nosound -ovc frameno -vc null -o /dev/null "$OUTPUT" | awk '/Video stream:/ {F=$12} END {print F}')
		scriptlog INFO "Input frames $INFRAMES $INPUT."
		scriptlog INFO "Output frames $OUTFRAMES $OUTPUT."
		if echo ${INFRAMES} : ${OUTFRAMES} | grep '[0-9] : [0-9]' >/dev/null 2>&1
		then
			DIFF=$([ $INFRAMES -gt $OUTFRAMES ] && echo $(( $INFRAMES - $OUTFRAMES )) || echo $(( $OUTFRAMES - $INFRAMES )))
		else
			scriptlog ERROR "Could not get frame count."
			scriptlog INFO "This check can be disabled with --outputchecks=NOFRAMECOUNT"
			return 1
		fi
		if [ "$DIFF" -gt 10 ]
		then
			scriptlog ERROR "Frame count difference of $DIFF between $INPUT and $OUTPUT greater than 10."
			scriptlog INFO "This check can be disabled with --outputchecks=NOFRAMECOUNT"
			return 1
		fi
	fi

	if echo "$OUTPUTCHECKS" | grep -v "NOSCAN" >/dev/null 2>&1
	then
		scriptlog INFO "Scanning output for errors. (Takes a long time)"
		SCANOUTFILE="${FIFODIR}/mplayerscan-out"
		nice mplayer -nojoystick -nolirc -nomouseinput -vo null -ao null -speed 10 "$OUTPUT" 2>&1 | tr '\r' '\n' >$SCANOUTFILE 2>&1
		LCOUNT=$(wc -l $SCANOUTFILE 2>/dev/null | awk '{T=$1} END {if(T>0){print T}else{print 0}}')
		if [ "$LCOUNT" -lt 1000 ]
		then
			scriptlog ERROR "mplayer line count of $LCOUNT to low on $OUTPUT."
			scriptlog INFO "This check can be disabled with --outputchecks=NOSCAN"
			return 1
		fi
		ECOUNT=$(egrep -ic 'sync|error|skip|damaged|overflow' $SCANOUTFILE)
		if [ "$ECOUNT" -gt "$MPLAYER_ERROR_COUNT" ]
		then
			scriptlog ERROR "mplayer error count too great ($ECOUNT > $MPLAYER_ERROR_COUNT) on $OUTPUT."
			scriptlog INFO "You can change the error limit variable MPLAYER_ERROR_COUNT at top of script or"
			scriptlog INFO "The check can be disabled with --outputchecks=NOSCAN"
			return 1
		fi
	fi

	return 0
}

getcategory() {
local CHANID="$1"
local STARTTIME="$2"
local DATA
	[ -n "$CHANID" ] || return 1
	DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select category from recorded where chanid = $CHANID and starttime = "$STARTTIME";
	EOF
	)
	echo $DATA | tr -d '[:cntrl:]' | tr -d '[:punct:]'
}

getplot() {
local CHANID="$1"
local STARTTIME="$2"
local DATA
	[ -n "$CHANID" ] || return 1
	DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select description from recorded where chanid = $CHANID and starttime = "$STARTTIME";
	EOF
	)
	echo $DATA | tr -d '[:cntrl:]' | tr -d '[:punct:]'
}

getyear() {
local CHANID="$1"
local STARTTIME="$2"
local DATA
	[ -n "$CHANID" ] || return 1
	# STARTTIME is not always the same in both tables for matching programs. ???
	DATA=$(mysql --batch --skip-column-names --user="${DBUserName}" --password="${DBPassword}" -h "${DBHostName}" "${DBName}" <<-EOF
	select airdate from recorded a,recordedprogram b
	where a.chanid = $CHANID and a.starttime = "$STARTTIME" and a.chanid = b.chanid
	and a.title = b.title and a.subtitle = b.subtitle;
	EOF
	)
	[ -n "$DATA" -a $DATA -gt 1800 ] && echo $DATA || echo $(date +%Y)
}


genchapfile() {
local FILE="$1"
local DURATION=$(( $2 * 60 ))
local CONTYPE="$3"
local CHAPTERFILE="${FIFODIR}/chapters.txt"
local LENGTH
local CHAPTER
local COUNT
local CHAPMINS
local CHAPHOURS
local CHAPSECS
	{
	if [ "$CONTYPE" != "mkv" -a "$CONTYPE" != "mp4" ]
	then
		scriptlog ERROR "Container type does not support chapters."
		return 1
	fi
	LENGTH=$(getlength "$FILE") # Must use midentify
	LENGTH=$(echo $LENGTH | cut -d'.' -f1)
	if [ -z "$LENGTH"  -o "$LENGTH" -lt 1 ]
	then
		scriptlog ERROR "Invalid Length $LENGTH seconds"
		return 1
	else
		scriptlog INFO "Length $LENGTH seconds, chapter every $DURATION seconds. $(( ( $LENGTH / $DURATION ) + 1 )) Chapters"
	fi
	CHAPTER=0 ; COUNT=1
	touch "$CHAPTERFILE"
	while [ "$CHAPTER" -lt "$LENGTH" ]
	do
		scriptlog DEBUG "CHAPTERFILE $CHAPTERFILE CHAPTER $CHAPTER LENGTH $LENGTH"
		CHAPMINS=$(( $CHAPTER / 60 ))
		CHAPHOURS=$(( $CHAPMINS / 60 ))
		CHAPMINS=$(( $CHAPMINS - ( $CHAPHOURS * 60 ) ))
		CHAPSECS=$(( $CHAPTER - ( ( $CHAPHOURS * 60 * 60 ) + ( $CHAPMINS * 60 ) ) ))
		printf 'CHAPTER%s=%02d:%02d:%02d.000\n' ${COUNT} ${CHAPHOURS} ${CHAPMINS} ${CHAPSECS} >> "$CHAPTERFILE"
		echo "CHAPTER${COUNT}NAME=Chapter $COUNT" >> "$CHAPTERFILE"
		COUNT=$(( $COUNT + 1 ))
		CHAPTER=$(( $CHAPTER + $DURATION ))
	done
	} >/dev/null 2>&1
	echo "$CHAPTERFILE"
}

encloseincontainer() {
local OUTBASE="$1"
local FPS="$2"
local AUDEXT="$3"
local CONTYPE="$4"
local ASPECT="$5"
local ATRACKS="$6"
local TITLE="$7"
local CHAPTERFILE="$8"
local CHAPTERS=""
local RET
local MKVTRACKS
local MP4TRACKS
local MKVTITLE
local TRACK
local FILE
	for ATRACK in ${ATRACKS//,/ }
	do
		TRACK=${ATRACK:0:1}
		LANG=${ATRACK:2:3}
		FILE=${OUTBASE}_audio${TRACK}.${AUDEXT}

		if [ ! -f "$FILE" ]
		then
			scriptlog ERROR "$FILE does not exist."
			return 1
		fi

		[ -n "$LANG" ] && MKVTRACKS="$MKVTRACKS --language 0:$LANG"
		MKVTRACKS="$MKVTRACKS $FILE"

		MP4TRACKS="$MP4TRACKS -add $FILE"
		[ -n "$LANG" ] && MP4TRACKS="${MP4TRACKS}:lang=$LANG"
	done
	if [ -f "${OUTBASE}_video.h264" ]
	then
		if [ "$CONTYPE" = "mkv" ]
		then
			[ -f "$CHAPTERFILE" ] && CHAPTERS="--chapters $CHAPTERFILE"
	                MKVTITLE="$TITLE"
                	[ -n "$SUBTITLE" ] && COPYFILE="$MKVTITLE - $SUBTITLE"
        	        [ -n "$META_ARTIST" ] && MKVTITLE="$META_ARTIST - $MKVTITLE"

			cat > ${OUTBASE}_tags.xml <<-EOF
			<?xml version="1.0" encoding="UTF-8"?>
			<!DOCTYPE Tags SYSTEM "matroskatags.dtd">
			<Tags>
			  <Tag>
			    <Targets>
			EOF

			# music video
			if [ -n "$META_ALBUM" ]
			then
				cat >> ${OUTBASE}_tags.xml <<-EOF
				      <TargetTypeValue>50</TargetTypeValue>
				    </Targets>
				    <Simple>
				      <Name>TITLE</Name>
				      <String>$META_ALBUM</String>
				    </Simple>
				  </Tag>
				  <Tag>
				    <Targets>
				      <TargetTypeValue>30</TargetTypeValue>
				    </Targets>
				    <Simple>
				      <Name>TITLE</Name>
				      <String>$TITLE</String>
				    </Simple>
				EOF

			# series episode
			elif [ -n "$META_EPISODE" ]
			then
				cat >> ${OUTBASE}_tags.xml <<-EOF
				      <TargetTypeValue>70</TargetTypeValue>
				    </Targets>
				    <Simple>
				      <Name>TITLE</Name>
				      <String>$TITLE</String>
				    </Simple>
				  </Tag>
				EOF
				if [ -n "$META_SEASON" ]
				then
					cat >> ${OUTBASE}_tags.xml <<-EOF
					  <Tag>
					    <Targets>
					      <TargetTypeValue>50</TargetTypeValue>
					    </Targets>
					    <Simple>
					      <Name>PART_NUMBER</Name>
					      <String>$META_SEASON</String>
					    </Simple>
					  </Tag>
					EOF
				fi
				cat >> ${OUTBASE}_tags.xml <<-EOF
				  <Tag>
				    <Targets>
				      <TargetTypeValue>30</TargetTypeValue>
				    </Targets>
				    <Simple>
				      <Name>PART_NUMBER</Name>
				      <String>$META_EPISODE</String>
				    </Simple>
				    <Simple>
				      <Name>TITLE</Name>
				      <String>$SUBTITLE</String>
				    </Simple>
				EOF

			# general
			else
				cat >> ${OUTBASE}_tags.xml <<-EOF
				      <TargetTypeValue>50</TargetTypeValue>
				    </Targets>
				    <Simple>
				      <Name>TITLE</Name>
				      <String>$TITLE</String>
				    </Simple>
				EOF

		        	[ -n "$SUBTITLE" ] && cat >> ${OUTBASE}_tags.xml <<-EOF
				    <Simple>
				      <Name>SUBTITLE</Name>
				      <String>$SUBTITLE</String>
				    </Simple>
				EOF
			fi

			[ -n "$META_ARTIST" ] && cat >> ${OUTBASE}_tags.xml <<-EOF
			    <Simple>
			      <Name>ARTIST</Name>
			      <String>$META_ARTIST</String>
			    </Simple>
			EOF

			[ -n "$META_DIRECTOR" ] && cat >> ${OUTBASE}_tags.xml <<-EOF
			    <Simple>
			      <Name>DIRECTOR</Name>
			      <String>$META_DIRECTOR</String>
			    </Simple>
			EOF

			[ -n "$META_DATE" ] && cat >> ${OUTBASE}_tags.xml <<-EOF
			    <Simple>
			      <Name>DATE_RELEASED</Name>
			      <String>$META_DATE</String>
			    </Simple>
			EOF

			[ -n "$META_COMMENT" ] && cat >> ${OUTBASE}_tags.xml <<-EOF
			    <Simple>
			      <Name>COMMENT</Name>
			      <String>$META_COMMENT</String>
			    </Simple>
			EOF

			[ -n "$META_LOCATION" ] && cat >> ${OUTBASE}_tags.xml <<-EOF
			    <Simple>
			      <Name>RECORDING_LOCATION</Name>
			      <String>$META_LOCATION</String>
			    </Simple>
			EOF

			cat >> ${OUTBASE}_tags.xml <<-EOF
			  </Tag>
			</Tags>
			EOF

			if [ "$MKVMERGE251BUG" = "YES" ]
			then
				scriptlog DEBUG Muxing: LANG=C mkvmerge --global-tags "${OUTBASE}_tags.xml" --default-duration 0:${FPS}fps --aspect-ratio 0:${ASPECT} --title "$MKVTITLE" $CHAPTERS \
				"${OUTBASE}_video.h264" $MKVTRACKS -o "${OUTBASE}.mkv"
				LANG=C mkvmerge --global-tags "${OUTBASE}_tags.xml" --default-duration 0:${FPS}fps --aspect-ratio 0:${ASPECT} --title "$MKVTITLE" $CHAPTERS \
				"${OUTBASE}_video.h264" $MKVTRACKS -o "${OUTBASE}.mkv"
				RET=$? ; [ $RET -eq 1 ] && RET=0 # mkvmerge return code of 1 is only a warning
			else
				scriptlog DEBUG Muxing: mkvmerge --global-tags "${OUTBASE}_tags.xml" --default-duration 0:${FPS}fps --aspect-ratio 0:${ASPECT} --title "$MKVTITLE" $CHAPTERS \
				"${OUTBASE}_video.h264" $MKVTRACKS -o "${OUTBASE}.mkv"
				mkvmerge --global-tags "${OUTBASE}_tags.xml" --default-duration 0:${FPS}fps --aspect-ratio 0:${ASPECT} --title "$MKVTITLE" $CHAPTERS \
				"${OUTBASE}_video.h264" $MKVTRACKS -o "${OUTBASE}.mkv"
				RET=$? ; [ $RET -eq 1 ] && RET=0 # mkvmerge return code of 1 is only a warning
			fi
		elif [ "$CONTYPE" = "mp4" ]
		then
			[ -f "$CHAPTERFILE" ] && CHAPTERS="-chap $CHAPTERFILE"
			MP4Box -add "${OUTBASE}_video.h264:par=1:1" $MP4TRACKS -fps $FPS $CHAPTERS "${OUTBASE}.mp4"
			RET=$?
		fi
		if [ $RET -eq 0 ]
		then
			[ "$DEBUG" != "ON" ] && rm -f "${OUTBASE}_video.h264" "${OUTBASE}_audio*.${AUDEXT}" "${OUTBASE}_tags.xml"
		else
			[ "$DEBUG" != "ON" ] && rm -f "${OUTBASE}_video.h264" "${OUTBASE}_audio*.${AUDEXT}" "${OUTBASE}_tags.xml" "${OUTBASE}.mkv" >/dev/null 2>&1
			return 1
		fi
	else
		scriptlog ERROR "${OUTBASE}_video.h264 does not exist."
		return 1
	fi
	return 0
}

logtranstime () {
local START=$1
local END=$2
local ORIGINALFILESIZE=$3
local NEWFILESIZE=$4
	TMP=$(( $(date -u -d"${END}" +%s) - $(date -u -d"${START}" +%s) ))
	DAYS=$(( $TMP / 60 / 60 / 24 ))
	HOURS=$(( $TMP / 60 / 60 - ($DAYS * 24) ))
	MINUTES=$(( $TMP / 60 - ( ($HOURS * 60)+($DAYS * 24 * 60) ) ))
	SECONDS=$(( $TMP - ( ($MINUTES * 60)+($HOURS * 60 * 60)+($DAYS * 24 * 60 * 60) ) ))
	scriptlog INFO "RUNTIME: $DAYS days $HOURS hours $MINUTES minutes and $SECONDS seconds. Original filesize: $ORIGINALFILESIZE New filesize: $NEWFILESIZE"
}

boinccontrol() {
local BOINCCOMMAND="$1"
# BOINCPASSWD global
	[ -n "$BOINCPASSWD" ] || return 1
	for p in $(boinccmd --host "localhost" --passwd "$BOINCPASSWD" --get_project_status | awk '/master URL:/ {print $3}')
	do
		if boinccmd --host "localhost" --passwd "$BOINCPASSWD" --project "$p" "$BOINCCOMMAND" >/dev/null 2>&1
		then
			scriptlog INFO "Boinc project $p $BOINCCOMMAND."
		else
			scriptlog INFO "Boinc project $p FAILED to $BOINCCOMMAND."
		fi
	done
}

cleanup() {
local SIG="$1"
local JOBID="$2"
local OUTPUT="$3"
local OUTBASE
local TRANPID
	scriptlog DEBUG "$SIG Clean up."
	if [ "$SIG" = "ABRT" ]
	then
		scriptlog ERROR "Job Aborted. Removing incomplete $OUTPUT."
		OUTBASE=$(echo "$OUTPUT" | sed -e 's/\.[ma][pv][4i]$//')
		[ "$DEBUG" != "ON" ] && rm -f "${OUTBASE}.avi" "${OUTBASE}_video.h264" "${OUTBASE}_audio*.aac" "${OUTBASE}_audio*.ogg" "${OUTBASE}_tags.xml" "${OUTBASE}.mp4" "${OUTBASE}.mkv" >/dev/null 2>&1
	fi

	TRANPID=$(jobs -l | awk '/mythtranscode/ {P=$2" "P} END {print P}')
	if [ -n "$TRANPID" ]
	then
		scriptlog DEBUG "Killing mythtranscode [$TRANPID]"
		ps -p $TRANPID >/dev/null 2>&1 && kill $TRANPID >/dev/null 2>&1
	fi

	# resume boinc
	boinccontrol "resume"

	if [ "$FINALEXIT" -eq 0 ]
	then
		[ "$DEBUG" != "ON" ] && rm -rf "$FIFODIR" >/dev/null 2>&1
		scriptlog INFO "Exiting. Successful."
		if [ "$JOBID" -ne 99999999 ]
		then
			setjobqueuestatus "$JOBID" "FINISHED"
			setjobqueuecomment "$JOBID" "[${$}] Successfully Completed"
		fi
		exit 0
	else
		scriptlog INFO "Exiting. Errored."
		if [ "$JOBID" -ne 99999999 ]
		then
			setjobqueuestatus "$JOBID" "ERRORED"
			setjobqueuecomment "$JOBID" "[${$}] Errored"
		fi
		# Only error code jobqueue.cpp interprets is 246. This is translated to "unable to find executable".
		#scriptlog ERROR "This error could be for many reasons. Mythtv will report unable to find executable, this is incorrect."
		is21orless && exit 246 || exit 1
	fi
}


MYSQLLIST="$MYSQLTXT /home/mythtv/.mythtv/mysql.txt ${HOME}/.mythtv/mysql.txt /.mythtv/mysql.txt /usr/local/share/mythtv/mysql.txt /usr/share/mythtv/mysql.txt /etc/mythtv/mysql.txt /usr/local/etc/mythtv/mysql.txt mysql.txt"
for m in $MYSQLLIST
do
	[ -f $m ] && . $m && break
done
if [ -z "$DBName" ]
then
	echo "Can't find mysql.txt. Change MYSQLTXT variable at top of script with your mysql.txt path"
	exit 1
fi

##### BG Monitor #####################################
# This will be fired off in background to update the jobqueue comment and process stop/pause/resume requests.
if echo "$1" | egrep -i '\-\-monitor=' >/dev/null 2>&1
then
	readonly MONJOBID=$(echo "$1" | cut -d'=' -f2)
	readonly MONPID="$2"
	readonly MONTRANSOP="$3"
	readonly LOGFILE="$4"
	readonly DBLOGGING=$(getsetting "LogEnabled")

	[ "$MONJOBID" -ne 99999999 -a -n "$MONPID" ] || exit 1

	PAUSEALREADYPRINTED="" ; RESUMEALREADYPRINTED=""

	scriptlog INFO "Starting monitoring process."
	sleep 5
	while ps -p $MONPID >/dev/null 2>&1
	do
		JQCMD=$(getjobqueuecmds "$MONJOBID")
		if [ "$JQCMD" = "PAUSE" ]
		then
			JQSTATUS=$(getjobqueuestatus "$MONJOBID")
			if [ "$JQSTATUS" != "PAUSED" ]
			then
				MENCODERPID=$(ps --ppid $MONPID | awk '/mencoder/ {print $1}')
				if [ -n "$MENCODERPID" ]
				then
					PAUSEALREADYPRINTED=""
					STARTPAUSESECS=$(date +%s)
					kill -s STOP $MENCODERPID
					setjobqueuestatus "$MONJOBID" "PAUSED"
					SAVEDCC=$(getjobqueuecomment "$MONJOBID")
					setjobqueuecomment "$MONJOBID" "[$MONPID] Paused for 0 Seconds"
					scriptlog STOP "Job Paused due to job queue pause request."
				else
					[ -z "$PAUSEALREADYPRINTED" ] && scriptlog ERROR "Sorry, could not pause. Will keep trying"
					PAUSEALREADYPRINTED=TRUE
				fi
			else
				NOW=$(date +%s)
				PAUSESECS=$(( $NOW - $STARTPAUSESECS ))
				PAUSEMINS=$(( $PAUSESECS / 60 ))
				PAUSEHOURS=$(( $PAUSEMINS / 60 ))
				PAUSEMINS=$(( $PAUSEMINS - ( $PAUSEHOURS * 60 ) ))
				PAUSESECS=$(( $PAUSESECS - ( ( $PAUSEHOURS * 60 * 60 ) + ( $PAUSEMINS * 60 ) ) ))
				setjobqueuecomment "$MONJOBID" "[$MONPID] Paused for $PAUSEHOURS Hrs $PAUSEMINS Mins $PAUSESECS Secs"
			fi
		elif [ "$JQCMD" = "RESUME" ]
		then
			JQSTATUS=$(getjobqueuestatus "$MONJOBID")
			if [ "$JQSTATUS" != "RUNNING" ]
			then
				MENCODERPID=$(ps --ppid $MONPID | awk '/mencoder/ {print $1}')
				if [ -n "$MENCODERPID" ]
				then
					RESUMEALREADYPRINTED=""
					kill -s CONT $MENCODERPID
					setjobqueuestatus "$MONJOBID" "RUNNING"
					setjobqueuecomment "$MONJOBID" "$SAVEDCC"
					scriptlog START "Job resumed due to job queue resume request."
					setjobqueuecmds "$MONJOBID" "RUN"
				else
					[ -z "$RESUMEALREADYPRINTED" ] && scriptlog ERROR "Sorry, could not resume. Will keep trying"
					RESUMEALREADYPRINTED=TRUE
				fi
			fi
		elif [ "$JQCMD" = "STOP" ]
		then
			setjobqueuestatus "$MONJOBID" "ABORTING"
			setjobqueuecomment "$MONJOBID" "[$MONPID] Stopping"
			scriptlog STOP "Stopping due to job queue stop request."
			setjobqueuecmds "$MONJOBID" "RUN"
			kill -s ABRT $MONPID
			sleep 2
			kill $MONPID
		elif [ "$JQCMD" = "RESTART" ]
		then
			scriptlog ERROR "Sorry, can't restart job."
			setjobqueuecmds "$MONJOBID" "RUN"
		else
			CC=$(getjobqueuecomment "$MONJOBID")
			if echo "$CC" | grep 'audio pass' >/dev/null 2>&1
			then
				PASSNU="audio pass"
			elif echo "$CC" | grep 'Single video pass' >/dev/null 2>&1
			then
				PASSNU="Single video pass"
			elif echo "$CC" | grep '1st video pass' >/dev/null 2>&1
			then
				PASSNU="1st video pass"
			elif echo "$CC" | grep '2nd video pass' >/dev/null 2>&1
			then
				PASSNU="2nd video pass"
			else
				sleep 15
				continue
			fi
			PCTLINE=$(tail -10 "$MONTRANSOP" | grep 'mythtranscode:' | cut -c39- | tail -1)
			[ -n "$PASSNU" -a -n "$PCTLINE" ] && setjobqueuecomment "$MONJOBID" "[$MONPID] $PASSNU $PCTLINE"
		fi
		sleep 15
	done
	exit
fi

##### Globals ########################################
readonly CMD="$0"
readonly LOGFILE="${LOGBASEDIR}/mythnuv2mkv${$}.log"
readonly FIFODIR="${LOGBASEDIR}/mythnuv2mkv${$}"
readonly MENCODEROP="${FIFODIR}/mencoder.op"
readonly TRANSOP="${FIFODIR}/transcode.op"
readonly STOPREQUEST="${FIFODIR}/STOPREQUEST"
if ! tty >/dev/null 2>&1
then
	readonly BOLDON=""
	readonly ALLOFF=""
	readonly REDFG=""
	readonly GREENFG=""
	readonly COLOURORIG=""
	[ "$DEBUG" = "ON" ] && exec 3>"${LOGBASEDIR}/DEBUG" || exec 3>/dev/null
	exec 1>&3
	exec 2>&3
else
	readonly BOLDON=`tput bold`
	readonly ALLOFF=`tput sgr0`
	readonly REDFG=`tput setaf 1`
	readonly GREENFG=`tput setaf 2`
	readonly COLOURORIG=`tput op`
fi
# DBLOGGING is reverse to shell true/false
DBLOGGING=0
OUTPUT=""
JOBID=99999999
FINALEXIT=0
STARTSECS="NA"
MAXRUNHOURS="NA"
MKVMERGE251BUG="NO"

##### Main ###########################################
if echo "$1" | egrep -i '\-help|\-usage|\-\?' >/dev/null 2>&1
then
	echo "$HELP"
	exit 1
fi

if [ "$CONTYPE" = "mkv" ]
then
	chkreqs "$MKVREQPROGS" "$MKVREQLIBS" || exit 1
	versioncheck "mkvmerge"
elif [ "$CONTYPE" = "mp4" ]
then
	chkreqs "$MP4REQPROGS" "$MP4REQLIBS" || exit 1
elif [ "$CONTYPE" = "avi" ]
then
	chkreqs "$AVIREQPROGS" "$AVIREQLIBS" || exit 1
fi
if ! versioncheck "convert"
then
	scriptlog INFO "The program \"convert\" does not appear to be the ImageMagick one. This will only affect coverfile creation."
fi

trap 'cleanup ABRT "$JOBID" "$OUTPUT"' INT ABRT
trap 'touch $STOPREQUEST ; scriptlog INFO "USR1 received. Will stop after current file completes."' USR1
trap 'cleanup EXIT "$JOBID"' EXIT
mkdir -m 775 -p "${LOGBASEDIR}" >/dev/null 2>&1 || scriptlog ERROR "Could not create ${LOGBASEDIR}"
mkdir -m 775 -p "${FIFODIR}" >/dev/null 2>&1 || scriptlog ERROR "Could not create ${FIFODIR}"
[ -w "${LOGBASEDIR}" ] || scriptlog ERROR "${LOGBASEDIR} not writable"
[ -w "${FIFODIR}" ] || scriptlog ERROR "${FIFODIR} not writable"
[ ${FINALEXIT} ] || exit $FINALEXIT

# Set default quality
[ -n "${QUALITY}" ] && setquality ${QUALITY}

for INPUT in "$@"
do
	if stoptime $STARTSECS $MAXRUNHOURS
	then
		scriptlog STOP "Stopping due to max runtime $MAXRUNHOURS."
		scriptlog BREAK
		break
	fi
	if [ -f "$STOPREQUEST" ]
	then
		scriptlog STOP "Stopping due to USR1 request."
		scriptlog BREAK
		break
	fi

	# Jobid from myth user job %JOBID%
	if echo "$INPUT" | grep -i '\-\-jobid=' >/dev/null 2>&1
	then
		JOBID=$(echo "$INPUT" | cut -d'=' -f2)
		DBLOGGING=$(getsetting "LogEnabled")
		continue
	fi

	if echo "$INPUT" | grep -i '\-\-findtitle=' >/dev/null 2>&1
	then
		SEARCHTITLE=$(echo "$INPUT" | cut -d'=' -f2)
		MATCHTITLE=$(findchanidstarttime "$SEARCHTITLE")
		echo "$MATCHTITLE"
		exit 0
	fi

	if echo "$INPUT" | grep -i '\-\-maxrunhours=' >/dev/null 2>&1
	then
		STARTSECS=$(date +%s)
		MAXRUNHOURS=$(echo "$INPUT" | cut -d'=' -f2)
		scriptlog INFO "Max Run Hours set to $MAXRUNHOURS."
		continue
	fi

	if echo "$INPUT" | grep -i '\-\-debugsg' >/dev/null 2>&1
	then
		DEBUGSG="ON"
		scriptlog INFO "DEBUGSG set ON."
		continue
	fi
	if echo "$INPUT" | grep -i '\-\-debug=' >/dev/null 2>&1
	then
		DEBUG=$(echo "$INPUT" | cut -d'=' -f2 | tr '[a-z]' '[A-Z]')
		scriptlog INFO "Debug set to $DEBUG."
		continue
	fi
	if echo "$INPUT" | grep -i '\-\-info=' >/dev/null 2>&1
	then
		INFO=$(echo "$INPUT" | cut -d'=' -f2 | tr '[a-z]' '[A-Z]')
		scriptlog INFO "Info set to $INFO."
		continue
	fi
	if echo "$INPUT" | grep -i '\-\-savenuv=' >/dev/null 2>&1
	then
		SAVENUV=$(echo "$INPUT" | cut -d'=' -f2 | tr '[a-z]' '[A-Z]')
		scriptlog INFO "SaveNUV set to $SAVENUV."
		continue
	fi

	if echo "$INPUT" | grep -i '\-\-outputchecks=' >/dev/null 2>&1
	then
		OUTPUTCHECKS=$(echo "$INPUT" | cut -d'=' -f2 | tr '[a-z]' '[A-Z]')
		scriptlog INFO "Output checks set to $OUTPUTCHECKS."
		continue
	fi

	shopt -s nocasematch
	if [[ "$INPUT" =~ --(aspect|denoise|deblock|deinterlace|invtelecine|crop|deleterec|chapterduration|chapterfile|copydir|contype|pass|quality|audiotracks)\=(.*) ]]
	then
		set${BASH_REMATCH[1]} "${BASH_REMATCH[2]}"
		continue
	fi
	shopt -u nocasematch

	if echo "$INPUT" | grep -i '\-\-chanid=' >/dev/null 2>&1
	then
		CHANID=$(echo "$INPUT" | cut -d'=' -f2)
		continue
	fi
	if echo "$INPUT" | grep -i '\-\-starttime=' >/dev/null 2>&1
	then
		STARTTIME=$(echo "$INPUT" | cut -d'=' -f2)
		if [ -z "$CHANID" ]
		then
			scriptlog ERROR "Skipping $STARTTIME. chanid not specified."
			scriptlog ERROR "--chanid must be specified before --starttime."
			scriptlog BREAK
			unset STARTTIME
			continue
		fi
		if [ "$DEBUGSG" = "ON" ]
		then
			INPUT=$(getrecordfile "$CHANID" "$STARTTIME" "$DEBUGSG")
			scriptlog INFO "$INPUT"
			scriptlog BREAK
			exit $FINALEXIT
		fi
		INPUT=$(getrecordfile "$CHANID" "$STARTTIME")
		if [ -z "$INPUT" ]
		then
			scriptlog ERROR "Skipping $CHANID $STARTTIME. Did not match a recording."
			scriptlog BREAK
			unset CHANID STARTTIME
			continue
		fi
		if [ ! -f "$INPUT" ]
		then
			scriptlog ERROR "Could not find Recording. ($INPUT)"
			scriptlog BREAK
			unset CHANID STARTTIME
			continue
		fi
		TITLE=$(gettitle $CHANID $STARTTIME)
		SUBTITLE=$(getsubtitle $CHANID $STARTTIME)
		parsetitle $SUBTITLE
		MTINFILE=""
		MTSOURCE="--chanid $CHANID --starttime $STARTTIME"
		hascutlist $CHANID $STARTTIME && MTSOURCE="--honorcutlist $MTSOURCE"
		scriptlog INFO "$CHANID $STARTTIME matches $META_ARTIST - $TITLE - $SUBTITLE ($INPUT)"
	else
		echo "$INPUT" | grep '^\/' >/dev/null 2>&1 || INPUT="`pwd`/${INPUT}"
		MTINFILE="--infile"
		MTSOURCE="$INPUT"
	fi

	if [ ! -f "$INPUT" ]
	then
		scriptlog ERROR "Skipping $INPUT does not exist."
		scriptlog BREAK
		unset CHANID STARTTIME
		continue
	fi

	if echo "$INPUT" | grep -v '\.[nm][up][vg]$' >/dev/null 2>&1
	then
		scriptlog ERROR "Skipping $INPUT not a nuv or mpg file."
		scriptlog BREAK
		unset CHANID STARTTIME
		continue
	fi

	OUTBASE=$(echo "$INPUT" | sed -e 's/\.[nm][up][vg]$//')
	OUTPUT="${OUTBASE}.${CONTYPE}"
	if [ -f "$OUTPUT" ]
	then
		scriptlog ERROR "Skipping $INPUT. $OUTPUT already exists."
		scriptlog BREAK
		unset CHANID STARTTIME
		continue
	fi

	INSIZE=$(( `stat -c %s "${INPUT}"` / 1024 ))
	FREESPACE=$(df -k --portability "$INPUT" | awk 'END {print $3}')
	if [ $(( $FREESPACE - $INSIZE )) -lt 10000 ]
	then
		scriptlog ERROR "Stopping due to disk space shortage."
		scriptlog BREAK
		break
	fi

	[ "$QUICKTIME_MP4" = "YES" ] && X264_OPTS="$X264EXT_OPTS"

	FILEINFO=$(getvidinfo "$INPUT" 0 width height fps scan_type)
	OLDIFS="$IFS"; IFS=":"; set - $FILEINFO; IFS="$OLDIFS"
	INWIDTH="$1"; INHEIGHT="$2"; INFPS="$3"; SCANTYPE="$4";
	if [ "$#" -ne 4 ]
	then
		scriptlog ERROR "Skipping $INPUT. Could not obtain vid format details Width $INWIDTH Height $INHEIGHT fps $INFPS ScanType $SCANTYPE"
		scriptlog BREAK
		unset CHANID STARTTIME
		continue
	fi

	if [ "$INWIDTH" = 720 -a "$INHEIGHT" = 576 ]
	then
		if [ "$SCANTYPE" = "Progressive" ]
		then
			FORMAT="576p"
		elif [ "$SCANTYPE" = "Interlaced" ]
		then
			FORMAT="576i"
		else
			FORMAT="576i or 576p"
		fi
	elif [ "$INWIDTH" = 720 -a "$INHEIGHT" = 480 ]
	then
		if [ "$SCANTYPE" = "Progressive" ]
		then
			FORMAT="480p"
		elif [ "$SCANTYPE" = "Interlaced" ]
		then
			FORMAT="480i"
		else
			FORMAT="480i or 480p"
		fi
	elif [ "$INWIDTH" = 1280 -a "$INHEIGHT" = 720 ]
	then
		SCANTYPE="Progressive" # Only set if mediainfo available
		FORMAT="720p"
	elif [ "$INWIDTH" = 1440 -a "$INHEIGHT" = 1088 ]
	then
		if [ "$SCANTYPE" = "Progressive" ]
		then
			FORMAT="1080p"
		elif [ "$SCANTYPE" = "Interlaced" ]
		then
			FORMAT="1080i"
		else
			FORMAT="1080i or 1080p"
		fi
	elif [ "$INWIDTH" = 1920 -a "$INHEIGHT" = 1088 ]
	then
		if [ "$SCANTYPE" = "Progressive" ]
		then
			FORMAT="1080p"
		elif [ "$SCANTYPE" = "Interlaced" ]
		then
			FORMAT="1080i"
		else
			FORMAT="1080i or 1080p"
		fi
	else
		FORMAT="Unknown"
	fi

	ASPECTSTR="NA";ASPECTFOUNDIN="NA"
	if [ "$ASPECTINLINE" = "4:3" -o "$ASPECTINLINE" = "16:9" ]
	then
		ASPECTSTR="$ASPECTINLINE"
		ASPECTFOUNDIN="Command Line"
	else
		TMP=$(getaspect "$INPUT")
		ASPECTSTR=$(echo "$TMP" | cut -d',' -f1)
		ASPECTFOUNDIN=$(echo "$TMP" | cut -d',' -f2)
	fi
	if [ "$ASPECTSTR" != "4:3" -a "$ASPECTSTR" != "16:9" ]
	then
		scriptlog ERROR "Skipping $INPUT. Aspect is $ASPECTSTR must be 16:9 or 4:3."
		scriptlog ERROR "If this is a mpg file make sure to set DEFAULTMPEG2ASPECT at top of this script."
		scriptlog BREAK
		unset CHANID STARTTIME
		continue
	fi
	scriptlog INFO "$FORMAT ${INWIDTH}x${INHEIGHT} $SCANTYPE $ASPECTSTR (Found in $ASPECTFOUNDIN) $INFPS FPS"

	i=0
	OLDTRACKS=$ATRACKS
	ATRACKS=""
	for ATRACK in ${OLDTRACKS//,/ }
	do
		set - ${ATRACK/:/ }
		ATRACK[$i]="$1"
		INALANG[$i]="$2"
		FILEINFO=$(getvidinfo "$INPUT" ${ATRACK[$i]} audio_format audio_sample_rate audio_channels audio_resolution audio_language)
		OLDIFS="$IFS"; IFS=":"; set - $FILEINFO; IFS="$OLDIFS"
		FORMAT="$1"; INARATE[$i]="$2"; CHANNELS[$i]="$3"; MGF_AUDIO_RESOLUTION[$i]="$4"; [ -z "${INALANG[$i]}" ] && INALANG[$i]="$5"
		if [ "$#" -ne 5 ]
		then
			scriptlog ERROR "Skipping $INPUT. Could not obtain aud format details Language ${INALANG[$i]} ARate ${INARATE[$i]} Channels ${CHANNELS[$i]} ASamplingRate ${MGF_AUDIO_RESOLUTION[$i]}"
			scriptlog BREAK
			unset CHANID STARTTIME
			continue
		fi
		scriptlog INFO "$FORMAT Language ${INALANG[$i]} Audio Rate ${INARATE[$i]} Channels ${CHANNELS[$i]} ASamplingRate ${MGF_AUDIO_RESOLUTION[$i]}"
		[ -n "$ATRACKS" ] && ATRACKS=$ATRACKS,
		ATRACKS=${ATRACKS}${ATRACK[$i]}
		[ "${INALANG[$i]}" != "NA" ] && ATRACKS=${ATRACKS}:${INALANG[$i]}

		# Audio resolution
		OGG_AUDIO_RESOLUTION[$i]=""
		FAAC_AUDIO_RESOLUTION[$i]=""
		if echo "${MGF_AUDIO_RESOLUTION[$i]}" | egrep '^[0-9]+$' >/dev/null 2>&1
		then
			OGG_AUDIO_RESOLUTION="--raw-bits=${MGF_AUDIO_RESOLUTION[$i]}"
			FAAC_AUDIO_RESOLUTION="-B ${MGF_AUDIO_RESOLUTION[$i]}"
		fi

		# Channel mapping
		FAACCCOPT[$i]=""
		case "${CHANNELS[$i]}" in
			1*|2*|3*|4*) true ;;
			5*|6*) FAACCCOPT[$i]="$FAACCHANCONFIG" ;;
			*) scriptlog ERROR "Audio channels ${CHANNELS[$i]} invalid."
			   scriptlog BREAK
			   unset CHANID STARTTIME
			   continue
			;;
		esac
		let i=i+1
	done
	scriptlog DEBUG "Audio track definitions: $ATRACKS"

	# Aspect/Scale/Crop opts
	if [ "$ASPECTSTR" = "4:3" ]
	then
		ASPECT=1.333333333
		SCALE=$SCALE43
		if [ "$SCALE" = "NA" ]
		then
			scriptlog ERROR "Skipping $INPUT Aspect 4:3 which is not supported for quality $QLEVEL"
			scriptlog BREAK
			unset CHANID STARTTIME
			continue
		fi
	elif [ "$ASPECTSTR" = "16:9" ]
	then
		ASPECT=1.77777777778
		SCALE=$SCALE169
	fi
	SCALESTR=$( echo $SCALE | tr ':' 'x' )
	SCALEMEN="scale=${SCALE},"

	OLDIFS="$IFS"; IFS=":"; set - $SCALE; IFS="$OLDIFS"
	OUTWIDTH="$1"; OUTHEIGHT="$2"
	if [ "$OUTWIDTH" = "$INWIDTH" -a "$OUTHEIGHT" = "$INHEIGHT" ]
	then
		CROPSCALE=""
		scriptlog INFO "Input and Output same resolution. crop,scale disabled."
	elif echo "$CROP" | egrep -i 'ON|YES' >/dev/null 2>&1
	then
		if [ "$OUTWIDTH" -gt "$INWIDTH" -o "$OUTHEIGHT" -gt "$INHEIGHT" ]
		then
			scriptlog INFO "Output is a greater scale than input. This is not sensible."
		fi
		CROPX=$CROPSIZE
		CROPY=$CROPSIZE
		CROPW=$(( $INWIDTH - ( 2 * $CROPX ) ))
		CROPH=$(( $INHEIGHT - ( 2 * $CROPY ) ))
		CROPVAL="${CROPW}:${CROPH}:${CROPX}:${CROPY}"
		CROPMEN="crop=${CROPVAL},"
		CROPSCALE="${CROPMEN}${SCALEMEN}"
		scriptlog INFO "Crop to $CROPVAL. Scale to $SCALESTR."
	else
		CROPSCALE="${SCALEMEN}"
		scriptlog INFO "Scale to $SCALESTR."
	fi

	# Filter opts
	OUTFPS="$INFPS" ; MENOUTFPS=""
	POSTVIDFILTERS=$(echo ${POSTVIDFILTERS} | sed -e 's/'"${INVTELECINEFILTER}"',//')
	POSTVIDFILTERS=$(echo ${POSTVIDFILTERS} | sed -e 's/'"${DEINTERLACEFILTER}"',//')
	[ -n "$CHANID" ] && SOURCENAME=$(getsourcename $CHANID)
	# Progressive then skip Deinterlace/Invtelecine
	if echo $INFPS | egrep '^23|^24' >/dev/null 2>&1
	then
		# Keep 23.976 FPS otherwise mencoder will convert to 29.97
		OUTFPS="23.976"
		scriptlog INFO "Input $INFPS FPS. OUTFPS set to $OUTFPS. Deinterlace/Invtelecine filter not needed."
	elif [ "$SCANTYPE" = "Progressive" ]
	then
		scriptlog INFO "$SCANTYPE. Deinterlace/Invtelecine filter not needed."
	# Deinterlace options
	elif echo "$DEINTERLACE" | egrep -i 'ON|YES' >/dev/null 2>&1
	then
		POSTVIDFILTERS="${POSTVIDFILTERS}${DEINTERLACEFILTER},"
		scriptlog INFO "Deinterlace filter added."
		[ "$SCANTYPE" != "Interlaced" ] && scriptlog INFO "If progressive this is wrong use --deinterlace=NO."
		echo "$INFPS" | grep  '^29' >/dev/null 2>&1 &&
			scriptlog INFO "You may need Invtelecine rather than Deinterlace. (--deinterlace=NO --invtelecine=YES)."
	elif [ -n "$SOURCENAME" ] && echo "$DEINTERLACE" | grep -i "$SOURCENAME" >/dev/null 2>&1
	then
		POSTVIDFILTERS="${POSTVIDFILTERS}${DEINTERLACEFILTER},"
		scriptlog INFO "Source $SOURCENAME. Deinterlace filter added."
		[ "$SCANTYPE" != "Interlaced" ] && scriptlog INFO "If progressive this is wrong use --deinterlace=NO."
		echo "$INFPS" | grep  '^29' >/dev/null 2>&1 &&
			scriptlog INFO "You may need Invtelecine rather than Deinterlace. (--deinterlace=NO --invtelecine=YES)."
	# Invtelecine options
	elif echo "$INVTELECINE" | egrep -i 'ON|YES' >/dev/null 2>&1 && echo $INFPS | egrep '^24|^25' >/dev/null 2>&1
	then
		# Very unusual to have PAL/DVB telecine video
		scriptlog INFO "Input $INFPS FPS. Invtelecine filter not supported."
	elif echo "$INVTELECINE" | egrep -i 'ON|YES' >/dev/null 2>&1
	then
		POSTVIDFILTERS="${POSTVIDFILTERS}${INVTELECINEFILTER},"
		OUTFPS="23.976"
		scriptlog INFO "Invtelecine filter added."
	fi
	[ "$OUTFPS" = "23.976" ] && MENOUTFPS="-ofps 24000/1001"
	[ -n "$POSTVIDFILTERS" ] && POSTVIDFILTERS="${POSTVIDFILTERS}softskip,"

	# Encoder opts
	# Force avi for videos staying in MythRecord
	if [ "$CONTYPE" = "avi" ] || [ -n "$CHANID" -a -z "$COPYDIR" ]
	then
		if [ "$AVIVID" = "xvid" ]
		then
			VBITRATE=$(calcbitrate $ASPECT $SCALE $XVID_CQ)
			PASSCMD="pass"
			VIDEOCODEC="-ovc xvid -xvidencopts ${XVID_OPTS}:bitrate=${VBITRATE}"
			VIDEXT="xvid"
		elif [ "$AVIVID" = "lavc" ]
		then
			VBITRATE=$(calcbitrate $ASPECT $SCALE $LAVC_CQ)
			PASSCMD="vpass"
			VIDEOCODEC="-ovc lavc -lavcopts ${LAVC_OPTS}:vbitrate=${VBITRATE}"
			VIDEXT="lavc"
		else
			scriptlog ERROR "Skipping $INPUT. Unsupported avi encoder"
			scriptlog BREAK
			unset CHANID STARTTIME
			continue
		fi
		ABITRATE=$MP3_ABITRATE
		AUDIOCODEC="-oac mp3lame -lameopts vbr=2:br=${ABITRATE}"
		AUDEXT="mp3"
		CONTYPE="avi"
		QUICKTIME_MP4="NO"
		MENOUT1STPASS="-aspect $ASPECT -force-avi-aspect $ASPECTSTR -o /dev/null"
		MENOUTOPT="-aspect $ASPECT -force-avi-aspect $ASPECTSTR -o"
		MENOUTFILE="$OUTPUT"
		MTOPT="--audiotrack ${ATRACKS:0:1}"
	elif [ "$CONTYPE" = "mp4" ]
	then
		VBITRATE=$(calcbitrate $ASPECT $SCALE $X264_CQ)
		AQUAL=$AAC_AQUAL
		PASSCMD="pass"
		VIDEOCODEC="-ovc x264 -x264encopts ${X264_OPTS}:bitrate=${VBITRATE}"
		VIDEXT="h264"
		AUDIOCODEC="-oac copy"
		AUDEXT="aac"
		MENOUT1STPASS="-of rawvideo -o /dev/null"
		MENOUTOPT="-of rawvideo -o"
		MENOUTFILE="${OUTBASE}_video.h264"
	elif [ "$CONTYPE" = "mkv" ]
	then
		VBITRATE=$(calcbitrate $ASPECT $SCALE $X264_CQ)
		if [ "$MKVAUD" = "ogg" ]
		then
			AQUAL=$OGG_AQUAL
			AUDEXT="ogg"
		elif [ "$MKVAUD" = "aac" ]
		then
			AQUAL=$AAC_AQUAL
			AUDEXT="aac"
		else
			scriptlog ERROR "Skipping $INPUT. Unsupported audio encoder"
			scriptlog BREAK
			unset CHANID STARTTIME
			continue
		fi
		PASSCMD="pass"
		VIDEOCODEC="-ovc x264 -x264encopts ${X264_OPTS}:bitrate=${VBITRATE}"
		VIDEXT="h264"
		AUDIOCODEC="-oac copy"
		MENOUT1STPASS="-of rawvideo -o /dev/null"
		MENOUTOPT="-of rawvideo -o"
		MENOUTFILE="${OUTBASE}_video.h264"
	else
		scriptlog ERROR "Skipping $INPUT. Incorrect video contype selected. $CONTYPE"
		scriptlog BREAK
		unset CHANID STARTTIME
		continue
	fi

	RETCODE=0
	# Fireoff a background monitoring job to update the job queue details
	[ "$JOBID" -ne 99999999 ] && $CMD --monitor=$JOBID ${$} "$TRANSOP" "$LOGFILE" &

	# Pause boinc
	boinccontrol "suspend"

	#Start time
	ENCSTARTTIME=$(date +%Y-%m-%d\ %H:%M:%S)
	ORIGINALFILESIZE=$(du -h "$INPUT" | cut -f1)

	i=0
	# mp4/mkv have seperate Audio/Video transcodes.
	for ATRACK in ${ATRACKS//,/ }
	do
		ATRACK=${ATRACK:0:1}
		MTOPTS="--audiotrack ${ATRACK}"
		if [ "$AUDEXT" = "aac" ]
		then
			if [ ! -f "${OUTBASE}_audio${ATRACK}.${AUDEXT}" ]
			then
				AENCLINE="faac ${FIFODIR}/audout -P ${FAAC_AUDIO_RESOLUTION[$i]} -R ${INARATE[$i]} -C ${CHANNELS[$i]} ${FAACCCOPT[$i]} -c ${INARATE[$i]} -X -q $AQUAL --mpeg-vers 4 -o ${OUTBASE}_audio$ATRACK.${AUDEXT}"
				scriptlog INFO "Audio Encoder: $AENCLINE."

				scriptlog START "Starting $AUDEXT audio trans of $INPUT, track $ATRACK. quality $AQUAL."
				[ "$JOBID" -ne 99999999 ] && setjobqueuecomment "$JOBID" "[${$}] audio pass started"

				rm -f "${FIFODIR}"/*out "$TRANSOP" "$MENCODEROP"
				if [ -n "$MTINFILE" ]
				then
					nice -n 19 mythtranscode --profile autodetect $MTINFILE "$MTSOURCE" $MTOPTS --fifodir "$FIFODIR" | tee -a "$TRANSOP" &
				else
					nice -n 19 mythtranscode --profile autodetect $MTSOURCE $MTOPTS --fifodir "$FIFODIR" | tee -a "$TRANSOP" &
				fi
				sleep 10
				# Throw away video
				nice -n 19 dd bs=512k if="${FIFODIR}/vidout" of=/dev/null &
				nice -n 19 faac "${FIFODIR}/audout" -P ${FAAC_AUDIO_RESOLUTION[$i]} -R ${INARATE[$i]} -C ${CHANNELS[$i]} ${FAACCCOPT[$i]} -c ${INARATE[$i]} -X -q $AQUAL --mpeg-vers 4 -o "${OUTBASE}_audio$ATRACK.${AUDEXT}"
				RETCODE=$?
				sleep 10
				if [ $RETCODE -ne 0 ]
				then
					scriptlog ERROR "Skipping $INPUT. Problem with audio pass."
					scriptlog BREAK
					unset CHANID STARTTIME
					continue
				fi
			else
				scriptlog INFO "Track $ATRACK Audio Encoding already done"
			fi
		elif [ "$AUDEXT" = "ogg" ]
		then
			if [ ! -f "${OUTBASE}_audio$ATRACK.${AUDEXT}" ]
			then
				AENCLINE="oggenc ${OGG_AUDIO_RESOLUTION[$i]} --raw-chan=${CHANNELS[$i]} --raw-rate=${INARATE[$i]} --quality=${AQUAL} -o ${OUTBASE}_audio$ATRACK.${AUDEXT} ${FIFODIR}/audout"
				scriptlog INFO "Audio Encoder: $AENCLINE."

				scriptlog START "Starting $AUDEXT audio trans of $INPUT. quality $AQUAL."
				[ "$JOBID" -ne 99999999 ] && setjobqueuecomment "$JOBID" "[${$}] audio pass started"

				rm -f "${FIFODIR}"/*out "$TRANSOP" "$MENCODEROP"
				if [ -n "$MTINFILE" ]
				then
					nice -n 19 mythtranscode --profile autodetect $MTINFILE "$MTSOURCE" $MTOPTS --fifodir "$FIFODIR" | tee -a "$TRANSOP" &
				else
					nice -n 19 mythtranscode --profile autodetect $MTSOURCE $MTOPTS --fifodir "$FIFODIR" | tee -a "$TRANSOP" &
				fi
				sleep 10
				# Throw away video
				nice -n 19 dd bs=512k if="${FIFODIR}/vidout" of=/dev/null &
				nice -n 19 oggenc ${OGG_AUDIO_RESOLUTION[$i]} --raw-chan=${CHANNELS[$i]} --raw-rate=${INARATE[$i]} --quality=${AQUAL} -o "${OUTBASE}_audio$ATRACK.${AUDEXT}" "${FIFODIR}/audout"
				RETCODE=$?
				sleep 10
				if [ $RETCODE -ne 0 ]
				then
					scriptlog ERROR "Skipping $INPUT. Problem with audio pass."
					scriptlog BREAK
					unset CHANID STARTTIME
					continue
				fi
			else
				scriptlog INFO "Track $ATRACK Audio Encoding already done"
			fi
		fi
		let i=i+1
	done

	if [ "$PASS" = "one" ]
	then
		if [ ! -f "$MENOUTFILE" ]
		then
			VENCLINE="mencoder -idx -noskip \
			${FIFODIR}/vidout -demuxer rawvideo -rawvideo w=${INWIDTH}:h=${INHEIGHT}:fps=${INFPS} \
			-audiofile ${FIFODIR}/audout -audio-demuxer rawaudio -rawaudio rate=${INARATE}:channels=${CHANNELS} \
			${VIDEOCODEC} \
			${AUDIOCODEC} \
			-vf ${POSTVIDFILTERS}${CROPSCALE}${ENDVIDFILTERS}harddup -sws 7 $MENOUTFPS \
			$MENOUTOPT $MENOUTFILE"
			scriptlog INFO "Video Encoder: $VENCLINE."

			scriptlog START "Starting $VIDEXT Single video pass trans of $INPUT. vbr $VBITRATE abr $ABITRATE."
			[ "$JOBID" -ne 99999999 ] && setjobqueuecomment "$JOBID" "[${$}] Single video pass started."

			rm -f "${FIFODIR}"/*out "$TRANSOP" "$MENCODEROP"
			if [ -n "$MTINFILE" ]
			then
				nice -n 19 mythtranscode --profile autodetect $MTINFILE "$MTSOURCE" --fifodir "$FIFODIR" | tee -a "$TRANSOP" &
			else
				nice -n 19 mythtranscode --profile autodetect $MTSOURCE --fifodir "$FIFODIR" | tee -a "$TRANSOP" &
			fi
			sleep 10
			nice -n 19 mencoder -idx -noskip \
			"${FIFODIR}/vidout" -demuxer rawvideo -rawvideo w=${INWIDTH}:h=${INHEIGHT}:fps=${INFPS} \
			-audiofile "${FIFODIR}/audout" -audio-demuxer rawaudio -rawaudio rate=${INARATE}:channels=${CHANNELS} \
			${VIDEOCODEC} \
			${AUDIOCODEC} \
			-vf ${POSTVIDFILTERS}${CROPSCALE}${ENDVIDFILTERS}harddup -sws 7 $MENOUTFPS \
			$MENOUTOPT "$MENOUTFILE" | tee -a "$MENCODEROP"
			RETCODE=$?
			sleep 10
		else
			scriptlog INFO "Video Encoding already done"
		fi
	else
		if [ ! -f "$MENOUTFILE" ]
		then
			VENCLINE="mencoder -idx \
			${FIFODIR}/vidout -demuxer rawvideo -rawvideo w=${INWIDTH}:h=${INHEIGHT}:fps=${INFPS} \
			-audiofile ${FIFODIR}/audout -audio-demuxer rawaudio -rawaudio rate=${INARATE}:channels=${CHANNELS} \
			${VIDEOCODEC}:${PASSCMD}=1:turbo -passlogfile ${FIFODIR}/2pass.log \
			${AUDIOCODEC} \
			-vf ${POSTVIDFILTERS}${CROPSCALE}${ENDVIDFILTERS}harddup -sws 7 $MENOUTFPS \
			$MENOUT1STPASS"
			scriptlog INFO "Video Encoder: $VENCLINE."

			scriptlog START "Starting $VIDEXT 1st video pass trans of $INPUT. vbr $VBITRATE abr $ABITRATE."
			[ "$JOBID" -ne 99999999 ] && setjobqueuecomment "$JOBID" "[${$}] 1st video pass started."

			rm -f "${FIFODIR}"/*out "$TRANSOP" "$MENCODEROP"
			if [ -n "$MTINFILE" ]
			then
				nice -n 19 mythtranscode --profile autodetect $MTINFILE "$MTSOURCE" --fifodir "$FIFODIR" | tee -a "$TRANSOP" &
			else
				nice -n 19 mythtranscode --profile autodetect $MTSOURCE --fifodir "$FIFODIR" | tee -a "$TRANSOP" &
			fi
			sleep 10
			nice -n 19 mencoder -idx \
			"${FIFODIR}/vidout" -demuxer rawvideo -rawvideo w=${INWIDTH}:h=${INHEIGHT}:fps=${INFPS} \
			-audiofile "${FIFODIR}/audout" -audio-demuxer rawaudio -rawaudio rate=${INARATE}:channels=${CHANNELS} \
			${VIDEOCODEC}:${PASSCMD}=1:turbo -passlogfile "${FIFODIR}/2pass.log" \
			${AUDIOCODEC} \
			-vf ${POSTVIDFILTERS}${CROPSCALE}${ENDVIDFILTERS}harddup -sws 7 $MENOUTFPS \
			$MENOUT1STPASS
			RETCODE=$?
			sleep 10
			if [ $RETCODE -ne 0 ]
			then
				scriptlog ERROR "Skipping $INPUT. Problem with 1st video pass of 2."
				scriptlog BREAK
				unset CHANID STARTTIME
				continue
			fi
		else
			scriptlog INFO "Video Encoding already done"
		fi

		if [ ! -f "$MENOUTFILE" ]
		then
			VENCLINE="mencoder -idx -noskip \
			${FIFODIR}/vidout -demuxer rawvideo -rawvideo w=${INWIDTH}:h=${INHEIGHT}:fps=${INFPS} \
			-audiofile ${FIFODIR}/audout -audio-demuxer rawaudio -rawaudio rate=${INARATE}:channels=${CHANNELS} \
			${VIDEOCODEC}:${PASSCMD}=2 -passlogfile ${FIFODIR}/2pass.log \
			${AUDIOCODEC} \
			-vf ${POSTVIDFILTERS}${CROPSCALE}${ENDVIDFILTERS}harddup -sws 7 $MENOUTFPS \
			$MENOUTOPT $MENOUTFILE"
			scriptlog INFO "Video Encoder: $VENCLINE."

			scriptlog START "Starting $VIDEXT 2nd video pass trans of $INPUT. vbr $VBITRATE abr $ABITRATE."
			[ "$JOBID" -ne 99999999 ] && setjobqueuecomment "$JOBID" "[${$}] 2nd video pass started."

			rm -f "${FIFODIR}"/*out "$TRANSOP" "$MENCODEROP"
			if [ -n "$MTINFILE" ]
			then
				nice -n 19 mythtranscode --profile autodetect $MTINFILE "$MTSOURCE" --fifodir "$FIFODIR" | tee -a "$TRANSOP" &
			else
				nice -n 19 mythtranscode --profile autodetect $MTSOURCE --fifodir "$FIFODIR" | tee -a "$TRANSOP" &
			fi
			sleep 10
			nice -n 19 mencoder -idx -noskip \
			"${FIFODIR}/vidout" -demuxer rawvideo -rawvideo w=${INWIDTH}:h=${INHEIGHT}:fps=${INFPS} \
			-audiofile "${FIFODIR}/audout" -audio-demuxer rawaudio -rawaudio rate=${INARATE}:channels=${CHANNELS} \
			${VIDEOCODEC}:${PASSCMD}=2 -passlogfile "${FIFODIR}/2pass.log" \
			${AUDIOCODEC} \
			-vf ${POSTVIDFILTERS}${CROPSCALE}${ENDVIDFILTERS}harddup -sws 7 $MENOUTFPS \
			$MENOUTOPT "$MENOUTFILE" | tee -a "$MENCODEROP"
			RETCODE=$?
			sleep 10
		else
			scriptlog INFO "Video Encoding already done"
		fi
	fi

	if [ $RETCODE -ne 0 ]
	then
		scriptlog ERROR "Skipping $INPUT. Problem with final video pass. $OUTPUT may exist."
		scriptlog BREAK
		unset CHANID STARTTIME
		continue
	fi

	if [ "$CONTYPE" = "mp4" -o "$CONTYPE" = "mkv" ]
	then
		if [ -f "$CHAPTERFILE" ]
		then
			scriptlog START "Using chapter file $CHAPTERFILE."
		elif [ -n "$CHAPTERDURATION" -a "$CHAPTERDURATION" -gt 0 ]
		then
			scriptlog START "Generating chapter file."
			[ "$JOBID" -ne 99999999 ] && setjobqueuecomment "$JOBID" "[${$}] Generating chapter file."
			CHAPTERFILE=$(genchapfile "${OUTBASE}_audio.${AUDEXT}" $CHAPTERDURATION $CONTYPE)
			[ -f "$CHAPTERFILE" ] || scriptlog ERROR "Generating chapter failed."
		fi
		scriptlog START "Joining ${OUTBASE}_video.h264 ${OUTBASE}_audio.${AUDEXT} in $CONTYPE container."
		[ "$JOBID" -ne 99999999 ] && setjobqueuecomment "$JOBID" "[${$}] Joining in $CONTYPE container."
		if ! encloseincontainer "$OUTBASE" $OUTFPS $AUDEXT $CONTYPE $ASPECTSTR $ATRACKS "$TITLE" "$CHAPTERFILE"
		then
			scriptlog ERROR "$CONTYPE container Failed for $OUTPUT."
			scriptlog BREAK
			unset CHANID STARTTIME
			continue
		fi
	fi

	scriptlog START "Checking $OUTPUT."
	[ "$JOBID" -ne 99999999 ] && setjobqueuecomment "$JOBID" "[${$}] Checking result."
	if ! checkoutput "$INPUT" "$OUTPUT" "$MENCODEROP" "$OUTPUTCHECKS"
	then
		mv "$OUTPUT" "${OUTPUT}-SUSPECT"
		scriptlog ERROR "$OUTPUT may be faulty. Saved as ${OUTPUT}-SUSPECT. $INPUT kept."
		scriptlog BREAK
		unset CHANID STARTTIME
		continue
	fi

	if [ -n "$CHANID" ]
	then
		SEARCHTITLE=$(getsearchtitle "$CHANID" "$STARTTIME")
		is21orless && INETREF=$(lookupinetref "$SEARCHTITLE" "$CHANID" "$STARTTIME") || INETREF="00000000"
		SERIESEPISODE=$(getseriesepisode "$CHANID" "$STARTTIME" "$INETREF")
		FILENAME=$(createfiletitleSEsubtitle "$CHANID" "$STARTTIME" "$SERIESEPISODE")
	else
		FILENAME=$(basename "$OUTPUT" | sed -e 's/\.[am][vkp][iv4]$//')
	fi

	if [ -n "$COPYDIR" ]
	then
		# Is this a good idea?
		#CATEGORY=$(getcategory "$CHANID" "$STARTTIME")
		#[ -n "$CATEGORY" ]
		#then
		#	COPYDIR="${COPYDIR}/${CATEGORY}"
		#fi
		[ -d "$(dirname "$COPYDIR/$FILENAME")" ] || mkdir -p "$(dirname "$COPYDIR/$FILENAME")"
		NEWNAME="$FILENAME"
		while [ -f "${COPYDIR}/${NEWNAME}.${CONTYPE}" ]
		do
			COUNT=$(( ${COUNT:=0} + 1 ))
			NEWNAME="${FILENAME}_${COUNT}"
		done
		FILENAME="${NEWNAME}.${CONTYPE}"
		if cp "$OUTPUT" "${COPYDIR}/${FILENAME}"
		then
			rm -f "$OUTPUT"
			scriptlog SUCCESS "Successful trans. $INPUT trans to ${COPYDIR}/${FILENAME}. $INPUT kept"
			if [ "$QUICKTIME_MP4" = "YES" ]
			then
				OLDFILE="${COPYDIR}/${FILENAME}"
				FILENAME=$(echo "$FILENAME" | sed -e 's/mp4$/mov/')
				mv "$OLDFILE" "${COPYDIR}/${FILENAME}"
			fi
			if is21orless
			then
				MYTHVIDDIR=$(getsetting VideoStartupDir)
				if echo "$COPYDIR" | grep "$MYTHVIDDIR" >/dev/null 2>&1
				then
					createvideometadata "${COPYDIR}/${FILENAME}" "$TITLE" "$ASPECTSTR" "$CHANID" "$STARTTIME" "$INETREF" "$SERIESEPISODE"
				fi
			else
				scriptlog INFO "MythTV V0.22 or greater. Not creating MythVideo entry. Use MythVideo menu"
			fi
			if echo "$DELETEREC" | egrep -i 'ON|YES' >/dev/null 2>&1 && [ "$FINALEXIT" -eq 0 ]
			then
				scriptlog INFO "Deleting recording."
				deleterecording "$CHANID" "$STARTTIME"
			fi
			NEWFILESIZE=$(du -h "${COPYDIR}/${FILENAME}" | cut -f1)
		else
			scriptlog ERROR "Successful trans but copy to ${COPYDIR}/${FILENAME} bad. $INPUT trans to $OUTPUT. $INPUT kept"
		fi
	else
		if [ -n "$CHANID" ]
		then
			scriptlog INFO "Updating MythRecord db to $OUTPUT."
			updatemetadata "$OUTPUT" "$CHANID" "$STARTTIME"
			# mythcommflag --rebuild does not work correctly for avi files.
			# Without this you can't edit files, but with it seeks don't work correctly.
			#scriptlog INFO "Rebuilding seektable for $OUTPUT."
			#mythcommflag --chanid "$CHANID" --starttime "$STARTTIME" --rebuild >/dev/null
			rm -f "${INPUT}.png"
		fi
		if [ "$DEBUG" = "ON" -o "$SAVENUV" = "ON" ]
		then
			mv "$INPUT" "${INPUT}OK-DONE"
			scriptlog SUCCESS "Successful trans to $OUTPUT. $INPUT moved to ${INPUT}OK-DONE."
		else
			rm -f "$INPUT"
			scriptlog SUCCESS "Successful trans to $OUTPUT. $INPUT removed."
		fi
		NEWFILESIZE=$(du -h "$OUTPUT" | cut -f1)
	fi
	# End time
	ENCENDTIME=$(date +%Y-%m-%d\ %H:%M:%S)
	logtranstime "$ENCSTARTTIME" "$ENCENDTIME" "$ORIGINALFILESIZE" "$NEWFILESIZE"
	scriptlog BREAK
	recall
	unset CHANID STARTTIME
done
exit $FINALEXIT


#STARTNUVINFO
#!/usr/bin/perl
# $Date: 2010/10/09 21:06:19 $
# $Revision: 1.61 $
# $Author: mythtv $
#
#  mythtv::nuvinfo.pm
#
#   exports one routine:  nuv_info($path_to_nuv)
#   This routine inspects a specified nuv file, and returns information about
#   it, gathered either from its nuv file structure
#
# Auric grabbed from nuvexport and Modified. Thanks to the nuvexport guys, I never would have been able to work this out
#
# finfo version width height desiredheight desiredwidth pimode aspect fps videoblocks audioblocks textsblocks keyframedist video_type audio_type audio_sample_rate audio_bits_per_sample audio_channels audio_compression_ratio audio_quality rtjpeg_quality rtjpeg_luma_filter rtjpeg_chroma_filter lavc_bitrate lavc_qmin lavc_qmax lavc_maxqdiff seektable_offset keyframeadjust_offset

# Byte swap a 32-bit number from little-endian to big-endian
    sub byteswap32 {
       # Read in a 4-character string
       my $in = shift;
       my $out = $in;

       if ($Config{'byteorder'} == 4321) {
           substr($out, 0, 1) = substr($in, 3, 1);
           substr($out, 3, 1) = substr($in, 0, 1);
           substr($out, 1, 1) = substr($in, 2, 1);
           substr($out, 2, 1) = substr($in, 1, 1);
       }

       return $out;
    }

# Byte swap a 64-bit number from little-endian to big-endian
    sub byteswap64 {
       # Read in a 8-character string
       my $in = shift;
       my $out = $in;

       if ($Config{'byteorder'} == 4321) {
           substr($out, 4, 4) = byteswap32(substr($in, 0, 4));
           substr($out, 0, 4) = byteswap32(substr($in, 4, 4));
       }

       return $out;
    }

# Opens a .nuv file and returns information about it
    sub nuv_info {
        my $file = shift;
        my(%info, $buffer);
    # open the file
        open(DATA, $file) or die "Can't open $file:  $!\n\n";
    # Read the file info header
        read(DATA, $buffer, 72);
    # Byte swap the buffer
        if ($Config{'byteorder'} == 4321) {
            substr($buffer, 20, 4) = byteswap32(substr($buffer, 20, 4));
            substr($buffer, 24, 4) = byteswap32(substr($buffer, 24, 4));
            substr($buffer, 28, 4) = byteswap32(substr($buffer, 28, 4));
            substr($buffer, 32, 4) = byteswap32(substr($buffer, 32, 4));
            substr($buffer, 40, 8) = byteswap64(substr($buffer, 40, 8));
            substr($buffer, 48, 8) = byteswap64(substr($buffer, 48, 8));
            substr($buffer, 56, 4) = byteswap32(substr($buffer, 56, 4));
            substr($buffer, 60, 4) = byteswap32(substr($buffer, 60, 4));
            substr($buffer, 64, 4) = byteswap32(substr($buffer, 64, 4));
            substr($buffer, 68, 4) = byteswap32(substr($buffer, 68, 4));
        }
    # Unpack the data structure
        ($info{'finfo'},          # "NuppelVideo" + \0
         $info{'version'},        # "0.05" + \0
         $info{'width'},
         $info{'height'},
         $info{'desiredheight'},  # 0 .. as it is
         $info{'desiredwidth'},   # 0 .. as it is
         $info{'pimode'},         # P .. progressive, I .. interlaced  (2 half pics) [NI]
         $info{'aspect'},         # 1.0 .. square pixel (1.5 .. e.g. width=480: width*1.5=720 for capturing for svcd material
         $info{'fps'},
         $info{'videoblocks'},    # count of video-blocks -1 .. unknown   0 .. no video
         $info{'audioblocks'},    # count of audio-blocks -1 .. unknown   0 .. no audio
         $info{'textsblocks'},    # count of text-blocks  -1 .. unknown   0 .. no text
         $info{'keyframedist'}
            ) = unpack('Z12 Z5 xxx i i i i a xxx d d i i i i', $buffer);
    # Perl occasionally over-reads on the previous read()
        seek(DATA, 72, 0);
    # Read and parse the first frame header
        read(DATA, $buffer, 12);
    # Byte swap the buffer
        if ($Config{'byteorder'} == 4321) {
            substr($buffer, 4, 4) = byteswap32(substr($buffer, 4, 4));
            substr($buffer, 8, 4) = byteswap32(substr($buffer, 8, 4));
        }
        my ($frametype,
            $comptype,
            $keyframe,
            $filters,
            $timecode,
            $packetlength) = unpack('a a a a i i', $buffer);
    # Parse the frame
        die "Illegal nuv file format:  $file\n\n" unless ($frametype eq 'D');
    # Read some more stuff if we have to
        read(DATA, $buffer, $packetlength) if ($packetlength);
    # Read the remaining frame headers
        while (12 == read(DATA, $buffer, 12)) {
        # Byte swap the buffer
            if ($Config{'byteorder'} == 4321) {
                substr($buffer, 4, 4) = byteswap32(substr($buffer, 4, 4));
                substr($buffer, 8, 4) = byteswap32(substr($buffer, 8, 4));
            }
        # Parse the frame header
            ($frametype,
             $comptype,
             $keyframe,
             $filters,
             $timecode,
             $packetlength) = unpack('a a a a i i', $buffer);
        # Read some more stuff if we have to
            read(DATA, $buffer, $packetlength) if ($packetlength);
        # Look for the audio frame
            if ($frametype eq 'X') {
            # Byte swap the buffer
                if ($Config{'byteorder'} == 4321) {
                    substr($buffer, 0, 4)  = byteswap32(substr($buffer, 0, 4));
                    substr($buffer, 12, 4) = byteswap32(substr($buffer, 12, 4));
                    substr($buffer, 16, 4) = byteswap32(substr($buffer, 16, 4));
                    substr($buffer, 20, 4) = byteswap32(substr($buffer, 20, 4));
                    substr($buffer, 24, 4) = byteswap32(substr($buffer, 24, 4));
                    substr($buffer, 28, 4) = byteswap32(substr($buffer, 28, 4));
                    substr($buffer, 32, 4) = byteswap32(substr($buffer, 32, 4));
                    substr($buffer, 36, 4) = byteswap32(substr($buffer, 36, 4));
                    substr($buffer, 40, 4) = byteswap32(substr($buffer, 40, 4));
                    substr($buffer, 44, 4) = byteswap32(substr($buffer, 44, 4));
                    substr($buffer, 48, 4) = byteswap32(substr($buffer, 48, 4));
                    substr($buffer, 52, 4) = byteswap32(substr($buffer, 52, 4));
                    substr($buffer, 56, 4) = byteswap32(substr($buffer, 56, 4));
                    substr($buffer, 60, 8) = byteswap64(substr($buffer, 60, 8));
                    substr($buffer, 68, 8) = byteswap64(substr($buffer, 68, 8));
                }
                my $frame_version;
                ($frame_version,
                 $info{'video_type'},
                 $info{'audio_type'},
                 $info{'audio_sample_rate'},
                 $info{'audio_bits_per_sample'},
                 $info{'audio_channels'},
                 $info{'audio_compression_ratio'},
                 $info{'audio_quality'},
                 $info{'rtjpeg_quality'},
                 $info{'rtjpeg_luma_filter'},
                 $info{'rtjpeg_chroma_filter'},
                 $info{'lavc_bitrate'},
                 $info{'lavc_qmin'},
                 $info{'lavc_qmax'},
                 $info{'lavc_maxqdiff'},
                 $info{'seektable_offset'},
                 $info{'keyframeadjust_offset'}
                 ) = unpack('ia4a4iiiiiiiiiiiill', $buffer);
            # Found the audio data we want - time to leave
                 last;
            }
        # Done reading frames - let's leave
            else {
                last;
            }
        }
    # Close the file
        close DATA;
    # Make sure some things are actually numbers
        $info{'width'}  += 0;
        $info{'height'} += 0;
    # HD fix
        if ($info{'height'} == 1080) {
            $info{'height'} = 1088;
        }
    # Make some corrections for myth bugs
        $info{'audio_sample_rate'} = 44100 if ($info{'audio_sample_rate'} == 42501 || $info{'audio_sample_rate'} =~ /^44\d\d\d$/);
    # NEIL Don't know why he hard set it?
    #    $info{'aspect'} = '4:3';
    # Cleanup
        $info{'aspect'}   = aspect_str($info{'aspect'});
        $info{'aspect_f'} = aspect_float($info{'aspect'});
    # Return
        return %info;
    }

    sub aspect_str {
        my $aspect = shift;
    # Already in ratio format
        return $aspect if ($aspect =~ /^\d+:\d+$/);
    # European decimals...
        $aspect =~ s/\,/\./;
    # Parse out decimal formats
        if ($aspect == 1)          { return '1:1';    }
        elsif ($aspect =~ m/^1.3/) { return '4:3';    }
        elsif ($aspect =~ m/^1.7/) { return '16:9';   }
        elsif ($aspect == 2.21)    { return '2.21:1'; }
    # Unknown aspect
        print STDERR "Unknown aspect ratio:  $aspect\n";
        return $aspect.':1';
    }

    sub aspect_float {
        my $aspect = shift;
    # European decimals...
        $aspect =~ s/\,/\./;
    # In ratio format -- do the math
        if ($aspect =~ /^\d+:\d+$/) {
            my ($w, $h) = split /:/, $aspect;
            return $w / $h;
        }
    # Parse out decimal formats
        if ($aspect eq '1')        { return  1;     }
        elsif ($aspect =~ m/^1.3/) { return  4 / 3; }
        elsif ($aspect =~ m/^1.7/) { return 16 / 9; }
    # Unknown aspect
        return $aspect;
    }

my %info = nuv_info($ENV{'NUVINFOFILE'});
my $c = 0;
foreach my $key (split(' ', $ENV{'NUVINFOPROPS'})) {
	($info{$key}) or $info{$key} = "NA";
	($c++ < 1) and print "$info{$key}" or print ":$info{$key}";
}
print "\n";
#ENDNUVINFO

###########################################################################################################
License Notes:
--------------

This software product is licensed under the GNU General Public License
(GPL). This license gives you the freedom to use this product and have
access to the source code. You can modify this product as you see fit
and even use parts in your own software. If you choose to do so, you
also choose to accept that a modified product or software that use any
code from mythnuv2mkv.sh MUST also be licensed under the GNU General Public
License.

In plain words, you can NOT sell or distribute mythnuv2mkv.sh, a modified
version or any software product based on any parts of mythnuv2mkv.sh as a
closed source product. Likewise you cannot re-license this product and
derivates under another license other than GNU GPL.

See also the article, "Free Software Matters: Enforcing the GPL" by
Eben Moglen. http://emoglen.law.columbia.edu/publications/lu-13.html
###########################################################################################################
