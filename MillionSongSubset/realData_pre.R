all_files <- list.files("MillionSongSubset", recursive = TRUE, full.names = TRUE)

# if (!requireNamespace("BiocManager", quietly = TRUE))
#   install.packages("BiocManager")
# 
# BiocManager::install("rhdf5")

library(rhdf5)

dat <- data.frame()
for (i in 1:1e4) {
  file_path <- all_files[i]
  tmp <- c(h5read(file_path, "analysis/songs"),
           h5read(file_path, "metadata/songs"),
           h5read(file_path, "musicbrainz/songs"))
  dat <- rbind(dat, data.frame(tmp))
  H5close()
}

# Now we start to deal with the data
# to extract the viable predictor
newdat <- dat[,c("duration", "end_of_fade_in", "key", "key_confidence", "loudness", "mode", "mode_confidence", "start_of_fade_out", "tempo", "time_signature", "time_signature_confidence", "artist_familiarity", "artist_hotttnesss", "year")]

nas <- union(which(newdat$year == 0), 
             union(which(is.na(newdat$artist_familiarity)), 
                   union(which(newdat$time_signature==0), which(newdat$loudness< -40))))
newdata <- newdat[-nas, ]

newdata$key <- factor(newdata$key)
dummy_key <- as.data.frame(model.matrix(~newdata$key-1))
newdata$time_signature <- factor(newdata$time_signature)
dummy_sig <- as.data.frame(model.matrix(~newdata$time_signature-1))

new_data <- cbind(newdata[, -c(3, 10)], dummy_key[,-1], dummy_sig[,-1])
summary(lm(data = new_data, year~.))

cor(new_data$tempo, new_data$loudness)

write.csv(new_data, file = "MillionSongSubset/realData_song.csv", row.names = FALSE)
