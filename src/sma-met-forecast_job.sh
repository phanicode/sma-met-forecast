#
# The shell environment in which the forecast scripts run needs
# to be set up for conda.  CONDA_INIT_SCRIPT_PATH is the location
# of the initialization script for conda on the host machine.
#
# SMA production installation in opt/conda/ on Redhat:
# CONDA_INIT_SCRIPT_PATH=/opt/conda/etc/profile.d/conda.sh
#
# miniconda installed in /usr/local/miniconda on macOS:
CONDA_INIT_SCRIPT_PATH=/usr/local/miniconda/etc/profile.d/conda.sh

#
# Site parameters
#
SITE="the SMA"
export LAT=19.824
export LON=-155.478
export ALT=4080

#
# Location and version of am binary, and am environment variables
#
export AM=/application/src/sma-met-forecast/bin/am
export AM_VERSION=$($AM -v | awk '/am version/ {print $3}')
export OMP_NUM_THREADS=2
export AM_CACHE_PATH=

#
# Directory where these scripts are located
#
export APPDIR=/application/src/sma-met-forecast/src

#
# Working directory, containing temporary data files and
# ephemeris data used by the plotting script.
#
RUNDIR=/application/src/sma-met-forecast/run

#
# Destination directory for the site forecast data tables.
#
SITE_FCAST_DIR=/data/met/sma-met-forecast

#
# Destination directory for the site forecast plots.
#
SITE_FCAST_PLOT_DIR=/sma/web/sma-met-forecast

#
# The script latest_gfs_cycle_time.py prints a time string
# corresponding to the analysis time for the most recent GFS
# forecast which is expected to be complete and ready for
# download.  That script assumes a default production time of 6
# hours, which can be overridden by setting the environment
# variable GFS_PRODUCTION_LAG.  The cron job which runs this
# script should then be triggered at a time a bit later than the
# assumed production time after the 0, 6, 12, 18 UT analysis
# times.  (Since the earliest products are downloaded first,
# there is an additional safety margin of about 10 minutes beyond
# the lag specified here.)
#
# Following the implementation of the FV3-based GFS v.15.1.1 in
# June 2019, the 384-hour forecast is typrically ready about 5.1
# hours after the analysis time.
#
# See https://www.nco.ncep.noaa.gov/pmb/nwprod/prodstat
#
export GFS_PRODUCTION_LAG=5.2

#
# Initialize conda and activate the environment for this script.
# (As noted in the README file, the conda environment
# sma-met-forecast can be created using the script
# make_conda_env.sh in the src/ directory.
#
source $CONDA_INIT_SCRIPT_PATH
conda activate sma-met-forecast

export PATH="$APPDIR:$PATH"
cd $RUNDIR

#
# It's possible that the latest GFS cycle time might change
# during the 45 minutes or so that this script takes to complete
# its work, so check it just once and save it in the environment
# for reference.  From here forward, relative_gfs_cycle_time.py
# will be used to generate time stamp strings relative to this
# one for the current and past 48-hours' GFS production cycles.
#
GFS_LATEST=$(latest_gfs_cycle_time.py)

#
# Make the data table for the most recent site forecast.  Site
# forecasts are saved in SITE_FCAST_DIR in subdirectories by
# year.
#
# If any of the prior 48 hours' forecasts are missing or short of
# full size, they will also be rebuilt.  This is needed the first
# time this script runs and later to clean up after outages.
#
EXPECTED_TABLE_LINES=210
for HOURS_AGO in 00 06 12 18 24 30 36 42 48; do
    export GFS_CYCLE=$(relative_gfs_cycle_time.py $GFS_LATEST -$HOURS_AGO)
    BASENAME=$(make_gfs_timestamp.py $GFS_CYCLE 0)
    YEAR=${BASENAME:0:4}
    OUTFILE=$SITE_FCAST_DIR/$YEAR/$BASENAME
    #
    # If the subdirectory for YEAR doesn't exist, make it
    #
    if [ ! -d $SITE_FCAST_DIR/$YEAR ]; then
        mkdir $SITE_FCAST_DIR/$YEAR
    fi
    #
    # If the file doesn't exist, make it
    #
    if [ ! -e $OUTFILE ]; then
        make_forecast_table.sh > $OUTFILE
    fi
    #
    # If the file exists but is missing lines, re-make it.
    #
    TABLE_LINES=$(wc -l $OUTFILE | awk '{print $1}')
    if [ $TABLE_LINES -lt $EXPECTED_TABLE_LINES ]; then
        make_forecast_table.sh > $OUTFILE
    fi
    chown nobody:nobody $OUTFILE
    chmod 444 $OUTFILE
    #
    # Make the soft link that is used by the plotting script to
    # access recent forecasts.  If $OUTFILE somehow hasn't been
    # successfully created, leave the link as is.
    #
    if [ $HOURS_AGO -eq 0 ]; then
        LINK=$SITE_FCAST_DIR/latest
    else
        LINK=$SITE_FCAST_DIR/latest-$HOURS_AGO
    fi
    if [ -f $OUTFILE ]; then
        ln -f -s $OUTFILE $LINK
	chown -h nobody:nobody $LINK
    fi
done

#
# Generate the plots and move the plot images to the data
# directory.
#
plot_forecast.py "$SITE" $LAT $LON $ALT $AM_VERSION $SITE_FCAST_DIR 120
plot_forecast.py "$SITE" $LAT $LON $ALT $AM_VERSION $SITE_FCAST_DIR 384
chown nobody:nobody forecast*.png
chmod 444 forecast*.png
mv forecast*.png $SITE_FCAST_PLOT_DIR

conda deactivate
