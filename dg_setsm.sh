#! /bin/bash

#David Shean
#dshean@gmail.com

#Wrapper to run SETSM for DG imagery

dir=$1
cd $dir

#This will return number of logical cpus
ncpu=$(python -c "import psutil; print(psutil.cpu_count(logical=False))")
#ncpu=$(python -c "from multiprocessing import cpu_count; print(cpu_count())")

#Set number of OpenMP threads
export OMP_NUM_THREADS=$ncpu

#Set up LFS striping to improve write performance
if [ -x "$(command -v lfs)" ]; then
    lfs setstripe -c $ncpu .
fi

rpcdir=/nobackup/deshean/rpcdem
rpcdem=$rpcdir/ned1/ned1_tiles_glac24k_115kmbuff.vrt
rpcdem_error=100

ntflist=$(ls *.ntf)

#Extract Catalog IDs
id1=$(nadir_id.sh . | awk '{print $1}')
id2=$(dg_get_ids.py . | grep -v $id1)
gsd=$(nadir_id.sh . | awk '{print $2}')

opt=""
opt+=" -provider DG"
opt+=" -GSD $gsd"
opt+=" -outres 8"
opt+=" -projection utm"
opt+=" -utm_zone 10"
#Only process a few tiles, for testing
#opt+=" -tilesSR 1 -tilesER 3 -tilesSC 1 -tilesEC 3"

#SETSM seeding can't read vrt, needs raw or exported tif from low-res run
#opt+=" -seed $rpcdem $rpcdem_error"

#ASP GDAL is built on OpenJPEG, can handle NITF
gdal_translate=~/sw/asp/latest/bin/gdal_translate
gdal_opt='-co COMPRESS=LZW -co TILED=YES -co BIGTIFF=IF_SAFER'
gdal_opt+=' -ot UInt16 -co NBITS=16'

if false ; then 
    #Generate corrected, mosaicked images for each ID
    ntfmos.sh .
    parallel --verbose --progress --delay 0.1 "if [ ! -e {.}_UInt16.tif ] ; then $gdal_translate $gdal_opt {} {.}_UInt16.tif; ln -s {.}.xml {.}_UInt16.xml ; fi" ::: *r100.tif
    #Note: SETSM may complain about images longer than ~50 km, this sets to 250 km
    opt+=" -LOO 250"
    seglist="r100_UInt16"
else  
    #Convert individual ntf to tif
    parallel --verbose --progress --delay 0.1 "if [ ! -e {.}.tif ] ; then $gdal_translate $gdal_opt {} {.}.tif; fi" ::: $ntflist
    seglist="R1C1 R2C1 R3C1 R4C1"
fi

if [ ! -d out ] ; then 
    mkdir out
fi

#img1=$(ls ${id1}.r100.tif)
#img2=$(ls ${id2}.r100.tif)

#seglist="r100_UInt16 R1C1 R2C1 R3C1 R4C1"
#seglist="R1C1"
for seg in $seglist
do
    img1=$(ls *${id1}*${seg}*.tif)
    img2=$(ls *${id2}*${seg}*.tif)

    #Prepare seed DEM
    if false ; then 
        proj="$(proj_select.py ${img1%.*}.xml)"
        #map_extent=$(dg_stereo_int.py ${img1%.*}.xml ${img2%.*}.xml "$proj")
        #echo $map_extent
        #Pad seed DEM by 5 km around image intersection
        map_extent=$(dg_stereo_int.py ${img1%.*}.xml ${img2%.*}.xml "$proj" 5000)
        echo $map_extent
        warptool.py -te "$map_extent" -t_srs "$proj" -outdir . $rpcdem
        rpcdem=$(basename $rpcdem)
        rpcdem=./${rpcdem%.*}_warp.tif
        gdal_translate -of ENVI $rpcdem ${rpcdem%.*}.raw
        rpcdem=${rpcdem%.*}.raw
        #This still results in segfault
        opt+=" -seed $rpcdem $rpcdem_error"
    fi

    outdir=out/${img1%.*}__${img2%.*}
    #opt+=" -gridonly $outdir/txt"
    cmd="~/sw/setsm/setsm $img1 $img2 $outdir $opt"
    echo $cmd
    eval time $cmd
done

#Run all subsections in parallel
#remove --link to run all possible combinations
#id1_list=$(ls *${id1}*.tif)
#id2_list=$(ls *${id2}*.tif)
#parallel --link --progress --verbose "~/sw/setsm/setsm {1} {2} out/{1.}__{2.} $opt" ::: $id1_list ::: $id2_list
