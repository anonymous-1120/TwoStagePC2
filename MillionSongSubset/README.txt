Million Song Dataset subset
===========================

Original dataset: http://millionsongdataset.com/pages/getting-dataset/#subset


Reproducing the real-data analysis
----------------------------------

Run from the repository root.

1. Preprocessing (only if you re-derive the CSV from raw HDF5 files).
   The committed file `MillionSongSubset/realData_song.csv` is already the
   preprocessed input, so this step is normally NOT needed:
     Rscript MillionSongSubset/realData_pre.R   # needs Bioconductor rhdf5; writes MillionSongSubset/realData_song.csv

2. Run the analysis:
     bash scripts/run_sim_7_realdata.sh   # or: Rscript MillionSongSubset/realData_revised.R
   Output: results/realdata/real_data_results.csv

3. Optional post-processing:
     bash scripts/run_sim_8_postprocess.sh   # summarize + figures under results/

See README.md for the full simulation pipeline.
