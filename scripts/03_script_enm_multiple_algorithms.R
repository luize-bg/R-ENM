### script enm dismo - multiple algorithms ###

# Maur�cio Humberto Vancine - mauricio.vancine@gmail.com
# 29/12/2017

###---------------------------------------------------------------------------###

# memory
rm(list = ls())
gc()
memory.limit(size = 1.75e13) 

# packages
if(!require("pacman")) install.packages("pacman")
pacman::p_load(raster, rgdal, dismo, gam, randomForest, kernlab, rJava, vegan, colorRamps,
               data.table, dplyr, colorRamps, spocc, ggplot2, RCurl, usdm, viridis)

# temp
setwd("E:/github_mauriciovancine/R-ENM/data")
dir.create("temp")
tempdir <- function() "E:/github_mauriciovancine/R-ENM/data/temp"
unlockBinding("tempdir", baseenv())
assignInNamespace("tempdir", tempdir, ns = "base", envir = baseenv())
assign("tempdir", tempdir, baseenv())
lockBinding("tempdir", baseenv())
tempdir()

# functions
eval(parse(text = getURL("https://gist.githubusercontent.com/mauriciovancine/840428ae5511e78b5681af6f995e6348/raw/12228ca55408ba1cb06357a28ed86be6933a4d25/script_function_scalebar_north_arrow.R", 
                         ssl.verifypeer = F)))

###---------------------------------------------------------------------------###

## data
#  variables
en <- getData(name = "worldclim", var = "bio", res = 10, download = T)
en
plot(en[[1]])

# resampling
en.re <- aggregate(en, fact = 6, fun = "mean", expand = T)
en.re
plot(en.re[[1]])

# limite
br <- getData("GADM", country = "BRA", level = 0)
br

# adjust to mask
en.br <- crop(mask(en.re, br), br)
en.br
plot(en.br[[1]])

# correlation
en.co <- vifcor(en.br[], th = .6) # bio05, bio14, bio18, bio19
en.co

en <- en.br[[as.character(en.co@results$Variables)]]
en  
  
# background coordinates
bc <- rasterToPoints(en)[, 1:2]
colnames(bc[, -3]) <- c("long", "lat")

plot(en[[1]], col = viridis(100))
points(bc, pch = 20, cex = .5, col = "blue")

# occurrences
ha <- distinct(occ2df(occ(query = "Haddadus binotatus", 
                          from = c("gbif", "idigbio", "inat", "obis", "ala"),
                          has_coords = T))[, 1:3])
ha

ha <- data.table(sp = sub(" ", "_", unique(tolower(ha$name))), 
                 lon = as.numeric(ha$longitude), 
                 lat = as.numeric(ha$latitude), 
                 pres = 1)
ha

plot(ha$lon, ha$lat, pch = 20)

# one point per cell
po <- mask(rasterize(ha[, 2:3], en[[1]], ha$pres), br)
po

po <- data.table(sp = unique(ha$sp), 
                    lon = rasterToPoints(po)[, 1], 
                    lat = rasterToPoints(po)[, 2])
po

plot(en[[1]], col = viridis(100))
points(bc, pch = 20, cex = .5, col = "blue")
points(po$lon, po$lat, pch = 20, cex = .5, col = "red")

###---------------------------------------------------------------------------###

# verify maxent
file.exists(paste0(system.file(package = "dismo"), "/java/maxent.jar"))

###---------------------------------------------------------------------------###

### enms ###

# output
setwd("E:/github_mauriciovancine/R-ENM/output")
dir.create("_output")
setwd("_output")

# export points
fwrite(po, "_po.csv")

# enms
for(i in 1:length(unique(po[, 1]))){ # for to each specie
  
  # variables for evaluate
  eval.Bioclim <- NULL
  eval.Gower <- NULL
  eval.Maha <- NULL
  eval.Maxent <- NULL
  eval.SVM <- NULL
  eval.names <- NULL

  # selecting presence and absence
	id.specie <- as.character(unique(po[, 1]))[i]
	pr.specie <- po[which(po[, 1] == id.specie), 2:3]
	id.background <- sample(nrow(bc), nrow(pr.specie))
	bc.specie <- bc[id.background, ]
	

  for(r in 1:10){	# number of replicas
    
	  ## preparing the models
    # train and test data	
	  pr.sample.train <- sample(nrow(pr.specie), round(0.7 * nrow(pr.specie)))
	  bc.sample.train <- sample(nrow(bc.specie), round(0.7 * nrow(bc.specie)))
	  train <- na.omit(prepareData(x = en, p = pr.specie[pr.sample.train, ], b = bc.specie[bc.sample.train, ]))
  	test <- na.omit(prepareData(x = en, p = pr.specie[-pr.sample.train, ], b = bc.specie[-bc.sample.train, ]))

    ### algorithms
  	
    ## 1. bioclim
  	# 1.1 calibration
	  Bioclim <- bioclim(train[which(train[, 1] == 1), -1])	
	 
	  # 1.2 projection
    writeRaster(predict(en, Bioclim), paste0("bioclim_", id.specie, ifelse(r < 10, paste0("0", r), r), ".tif"), format = "GTiff")	
   
    # 1.3 evaluation
	  eBioclim <- evaluate(p = test[test[, 1] == 1, -1], a = test[test[, 1] == 0, -1], model = Bioclim)
	  idBioclim <- which(eBioclim@t == as.numeric(threshold(eBioclim, "spec_sens")))
	  eval.Bioclim.sp <- c(eBioclim@t[idBioclim], eBioclim@auc, (eBioclim@TPR[idBioclim] + eBioclim@TNR[idBioclim] - 1))
	  eval.Bioclim <- rbind(eval.Bioclim, eval.Bioclim.sp)

	  # verify 
	  print(paste0("Yeh! The model of ", id.specie, ", algorithm 'Bioclim', replica ", 
	               ifelse(r < 10, paste0("0", r), r), " it's done!"))
	  
	  
    ## 2. gower
	  # 2.1 calibration
	  Gower <- domain(train[which(train[, 1] == 1), -1])	

	  # 2.2 projection
    writeRaster(predict(en, Gower), paste0("gower_", id.specie, ifelse(r < 10, paste0("0", r), r), ".tif"), format = "GTiff") 

    # 2.3 evaluation
	  eGower <- evaluate(p = test[test[, 1] == 1, -1], a = test[test[, 1] == 0, -1], model = Gower)
  	idGower <- which(eGower@t == as.numeric(threshold(eGower, "spec_sens")))
	  eval.Gower.sp <- c(eGower@t[idGower], eGower@auc, (eGower@TPR[idGower] + eGower@TNR[idGower] - 1))
	  eval.Gower <- rbind(eval.Gower, eval.Gower.sp)

	  # verify 
	  print(paste0("Yeh! The model of ", id.specie, ", algorithm 'Gower', replica ", 
	               ifelse(r < 10, paste0("0", r), r), " it's done!"))
	  
    ## 3. mahalanobis	
	  # 3.1 calibration
	  Maha <- mahal(train[which(train[, 1] == 1), -1])	
	
	  # 3.2 projection
    writeRaster(predict(en, Maha), paste0("mahalanobis_", id.specie, ifelse(r < 10, paste0("0", r), r), ".tif"), format = "GTiff") 

    # 3.3 evaluation
	  eMaha <- evaluate(p = test[test[, 1] == 1, -1], a = test[test[, 1] == 0, -1], model = Maha)
	  idMaha <- which(eMaha@t == as.numeric(threshold(eMaha, "spec_sens")))
	  eval.Maha.sp <- c(eMaha@t[idMaha], eMaha@auc, (eMaha@TPR[idMaha] + eMaha@TNR[idMaha] - 1))
	  eval.Maha <- rbind(eval.Maha, eval.Maha.sp)
	
	  # verify 
	  print(paste0("Yeh! The model of ", id.specie, ", algorithm 'Mahalanobis', replica ", 
	               ifelse(r < 10, paste0("0", r), r), " it's done!"))

    ## 4. maxent	
	  # 4.1 calibration
	  Maxent <- maxent(train[, -1], train[, 1])	

	  # 4.2 projection
    writeRaster(predict(en, Maxent), paste0("maxent_", id.specie, ifelse(r < 10, paste0("0", r), r), ".tif"), format = "GTiff") 

    # 4.3 evaluation
	  eMaxent <- evaluate(p = test[test[, 1] == 1, -1], a = test[test[, 1] == 0, -1], model = Maxent)
	  idMaxent <- which(eMaxent@t == as.numeric(threshold(eMaxent, "spec_sens")))
	  eval.Maxent.sp <- c(eMaxent@t[idMaxent], eMaxent@auc, (eMaxent@TPR[idMaxent] + eMaxent@TNR[idMaxent] - 1))
	  eval.Maxent <- rbind(eval.Maxent, eval.Maxent.sp)

	  # verify 
	  print(paste0("Yeh! The model of ", id.specie, ", algorithm 'Maxent', replica ", 
	               ifelse(r < 10, paste0("0", r), r), " it's done!"))

    ## 5. svm	
	  # 5.1 calibration
	  SVM <- ksvm(pb ~ bio5 + bio14 + bio18 + bio19 , data = train)	

	  # 5.2 projection
    writeRaster(predict(en, SVM), paste0("svm_", id.specie, ifelse(r < 10, paste0("0", r), r), ".tif"), format = "GTiff") 

    # 5.3 evaluation
	  eSVM <- evaluate(p = test[test[, 1] == 1, -1], a = test[test[, 1] == 0, -1], model = SVM)
	  idSVM <- which(eSVM@t == as.numeric(threshold(eSVM, "spec_sens")))
	  eval.SVM.sp <- c(eSVM@t[idSVM], eSVM@auc, (eSVM@TPR[idSVM] + eSVM@TNR[idSVM] - 1))
	  eval.SVM <- rbind(eval.SVM, eval.SVM.sp)
	  
	  # verify 
	  print(paste0("Yeh! The model of ", id.specie, ", algorithm 'SVM', replica ", 
	               ifelse(r < 10, paste0("0", r), r), " it's done!"))
	  

	  eval.names <- c(eval.names, paste0(id.specie, ifelse(r < 10, paste0("0", r), r)))	
	  
  } # ends for "r"

  dimnames(eval.Bioclim) <- list(eval.names, c("thrs", "AUC", "TSS"))
  dimnames(eval.Gower) <- list(eval.names, c("thrs", "AUC", "TSS"))  
  dimnames(eval.Maha) <- list(eval.names, c("thrs", "AUC", "TSS"))  
  dimnames(eval.Maxent) <- list(eval.names, c("thrs", "AUC", "TSS"))
  dimnames(eval.SVM) <- list(eval.names, c("thrs", "AUC", "TSS"))

  write.table(eval.Bioclim, paste0("zEval_", "bioclim_", id.specie, ".txt"))
  write.table(eval.Gower, paste0("zEval_", "gower_", id.specie, ".txt"))
  write.table(eval.Maha, paste0("zEval_", "mahalanobis_", id.specie, ".txt"))
  write.table(eval.Maxent, paste0("zEval_", "maxent_", id.specie, ".txt"))
  write.table(eval.SVM, paste0("zEval_", "svm_", id.specie, ".txt"))

} # ends for"i"

###----------------------------------------------------------------------------###

