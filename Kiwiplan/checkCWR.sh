SET @machineNum = 1031 ;
SET @startDate = '2025-11-07 00:00:00';
SET @FinishDate = '2025-11-07 23:59:59';
#
SELECT 'FBK WASTE', wst.id, wst.waste_code, wst.job_number, wst.series_number, wst.step_number, wst.machine_number, wst.wasted_quantity, wst.recorded, wst.scrap_val_per_wt, wst.unique_waste_id, wst.waste_id 
FROM murf_man.WASTGE wst 
WHERE wst.machine_number=@machineNum 
and ( (wst.recorded>=@startDate)) 
and ( (wst.recorded<=@FinishDate))
#AND  wst.wasted_quantity < 0
order by wst.machine_number ,wst.recorded ,wst.waste_code;
#
#SELECT 'BOARDS',mm.legacyId,mm.oname,mg.oname,mc.oname,mm.description,mt.visibilityType,mm.arealDensity,mm.thickness,FLOOR(mm.firstStrength),FLOOR(mm.secondStrength),mm.mdsCorrugator,mm.mdsConverting,mt.availabilityStatus,
#mm.firstUserDefinedProperties,mm.secondUserDefinedProperties,mm.updated,mt.totalPaperCost,mt.totalStarchCost,mt.totalCoatingCost,mt.totalCostPerBasis,mt.futureCostPerBasis,mm.materialKind,mt.costBasisType,
#st.internalName,loc.oname,mt.orderingStatus,mt.minimumSkuWeight,mt.maximumSkuWeight,mm.thirdUserDefinedProperties,mt.periodBeforeOld,mm.paperDensity,mm.starchDensity,mm.shrinkageFactor,mm.allowPaperSubstitution,
#FLOOR(mm.firstStrength * 1000),FLOOR(mm.secondStrength * 1000),FLOOR(mm.thirdStrength * 1000),FLOOR(mm.fourthStrength * 1000),FLOOR(mm.fifthStrength* 1000),FLOOR(mm.sixthStrength * 1000) 
#FROM murf_man.materialmaster mm
#INNER JOIN murf_man.materialtype mt ON mt.master=mm.objid
#INNER JOIN murf_man.materialgroup mg ON mm.materialgroup=mg.objid
#LEFT JOIN murf_man.materialgroup mc ON mm.caseGroup=mc.objid
#LEFT JOIN murf_man.location loc ON mt.location=loc.objid
#LEFT JOIN murf_man.store st ON loc.store=st.objid
#WHERE mm.materialKind in ("B","SB")
##and mm.legacyId=? and mt.division=? 
#and mt.retired=0;
#
#SELECT 'ROLL_STANDS',rs.standType,ps.stationNumber,wrs.rollSkuIds 
#FROM murf_csc.wetendfeedback wef,murf_csc.wetendrun wr,murf_csc.wetendreelstandconfigurations wrs,murf_csc.reelstand rs,murf_csc.paperstation ps 
#WHERE wr.objid=wef.wetendRun and wr.wetendConfiguration=wrs.wetendConfiguration 
#and wrs.reelstand=rs.objid and rs.station=ps.objid;
#and wef.objid=? order by wrs.lsequence
#
SELECT 'SETUPS',suo.objid*10+suf.feedbackPart, cog.corrugatorNumber, wef.legacyNumber, sur.sequenceNumber, (suo.lsequence + 1),cor.orderNumberForClassic, cor.seriesNumberForClassic, cor.actualLength,suo.scheduledWidth, cor.objid, suf.legacyNumber, sur.sequenceNumber, IFNULL(kf1.estimatedSheets,0)+IFNULL(kf2.estimatedSheets,0)+IFNULL(kf3.estimatedSheets,0) as quantityRequired, FLOOR((IFNULL(kf1.estimatedSheets,0)+IFNULL(kf2.estimatedSheets,0)+IFNULL(kf3.estimatedSheets,0)) / suo.totalOut),suo.totalOut, suc.trim, suc.trimSuppressionType, IF(wef.legacyNumber<>sur.wetendRunNumber,sur.wetendRunNumber,0),suc.manualScorerUnitRequired, suc.scheduleNumber, sur.scheduleType, suf.estimatedLength, suf.estimatedTime, sk1.numberOut as nout1, sk2.numberOut as nout2, sk3.numberOut as nout3, IFNULL(sk1.explicitStacksPerUnit,sk1.derivedStacksPerUnit) as spu1, IFNULL(sk2.explicitStacksPerUnit,sk2.derivedStacksPerUnit) as spu2, IFNULL(sk3.explicitStacksPerUnit,sk3.derivedStacksPerUnit) as spu3, IFNULL(sk1.explicitSheetsPerStack,sk1.derivedSheetsPerStack) as sps1, IFNULL(sk2.explicitSheetsPerStack,sk2.derivedSheetsPerStack) as sps2, IFNULL(sk3.explicitSheetsPerStack,sk3.derivedSheetsPerStack) as sps3, suf.length, FLOOR((IFNULL(kf1.goodSheets,0)+IFNULL(kf2.goodSheets,0)+IFNULL(kf3.goodSheets,0))/suo.totalOut), kf1.goodSheets, kf2.goodSheets, kf3.goodSheets, kf1.wastedSheets, kf2.wastedSheets, kf3.wastedSheets, suf.effectiveStartTime, suf.effectiveEndTime, suf.runTime, suf.downTime, suf.feedbackPart 
FROM murf_csc.setuporder suo INNER JOIN setupconfiguration suc ON suo.setupConfiguration = suc.objid 
INNER JOIN murf_csc.corrugator cog ON suc.corrugator = cog.objid 
INNER JOIN murf_csc.corrugatororder cor ON suo.corrugatorOrder = cor.objid 
INNER JOIN murf_csc.setuprun sur ON suc.objid = sur.setupConfiguration 
INNER JOIN murf_csc.setupfeedback suf ON sur.objid = suf.setupRun 
INNER JOIN murf_csc.wetendrun wr ON wr.objid=sur.wetendRun 
INNER JOIN murf_csc.wetendfeedback wef ON suf.wetendFeedback = wef.objid
LEFT JOIN murf_csc.corrugatorknife ck1 on ck1.lsequence = 0 and ck1.corrugator=cog.objid 
LEFT JOIN murf_csc.corrugatorknife ck2 on ck2.lsequence = 1 and ck2.corrugator=cog.objid 
LEFT JOIN murf_csc.corrugatorknife ck3 on ck3.lsequence = 2 and ck3.corrugator=cog.objid 
LEFT JOIN murf_csc.setupknife sk1 ON suo.objid = sk1.setupOrder AND sk1.knife = ck1.objid 
LEFT JOIN murf_csc.setupknife sk2 ON suo.objid = sk2.setupOrder AND sk2.knife = ck2.objid 
LEFT JOIN murf_csc.setupknife sk3 ON suo.objid = sk3.setupOrder AND sk3.knife = ck3.objid 
LEFT JOIN murf_csc.knifefeedback kf1 ON kf1.setupKnife = sk1.objid AND kf1.setupFeedback=suf.objid 
LEFT JOIN murf_csc.knifefeedback kf2 ON kf2.setupKnife = sk2.objid AND kf2.setupFeedback=suf.objid 
LEFT JOIN murf_csc.knifefeedback kf3 ON kf3.setupKnife = sk3.objid AND kf3.setupFeedback=suf.objid 
WHERE cog.corrugatorNumber=1 
AND (wef.startTime>=@startDate AND wef.startTime<=@FinishDate)
and (sur.status<>'PROC' or (sur.status='PROC' and suf.shiftSplit=1)) and wr.sequencenumber > 0 
order by cog.corrugatorNumber ,wef.legacyNumber ,sur.sequenceNumber ,suo.lsequence+1;
#
SELECT 'ORDERS',co.objid,co.orderNumberForClassic,co.seriesNumberForClassic,mm.legacyId,cu.shortName,ord.customerOrderNumber,co.orderStatus,og.oname,jb.dueTime,jb.dueTime,ord.orderPlacedTime,ord.orderPlacedTime,ord.updated,ord.updated,jb.orderedQuantity,co.targetQuantityForClassic,co.unprogrammedQuantityForClassic,co.JoinTo,co.classicCombiNumberUp,co.classicCombiTrim,co.numberUp,co.targetOverrunPercentageForClassic,co.targetUnderrunPercentageForClassic,IF(co.runOnAnyCorrugator=0,cg.corrugatorNumber,0),IF(ord.anyPlant=0,pl.plantNumber,0),co.runSpeedIndex,co.maximumOutPerKnife,co.maximumOutPerKnife,co.maximumOutPerKnife,co.allowPartials,co.maximumSetups,co.allowGradeChangeForClassic,co.allowUpgrades,co.allowDowngrades,co.maximumWidthReductionForClassic,co.orderedBoardLengthForClassic,IFNULL(co.actualWidth,co.orderedBoardWidth),co.dischargeDestinationCode,co.dischargeDirectionCode,co.sheetsPerStack,co.stacksPerUnit,co.allowRotation,co.allowMixedRotation,co.corrugatorDueFinishTime,co.corrugatorDueFinishTime,if(co.convertingDueStartTime=0,co.corrugatorDueFinishTime,co.convertingDueStartTime),co.programmedCount+co.cancelledCount,co.returnedCount,co.cancelledCount,mm2.legacyId,co.orderedBoardWidth,co.maximumWidthReductionForClassic,co.shiedPanelForClassic,co.classicOrderSelectionStatus,sp.oname,co.caseLastFailTime,co.caseLastFailedScheduleNumber,co.caseFailCount,co.maximumTotalOut,mm1.oname,co.classicFailedCorrugatorNames,co.classicFailedCorrugatorNames,co.expectedWasteForClassic,ord.customerOverrunPercentageForClassic,ord.customerUnderrunPercentageForClassic,ord.classicUserMaintainedMaterial,co.maximumDensityUpgradePercentage,co.maximumCostUpgradePercentage,co.maximumDensityDowngradePercentage,co.maximumCostDowngradePercentage,co.trimSheetOrder
FROM murf_csc.corrugatororder co 
INNER JOIN murf_man.materialmaster mm ON co.boardMasterIdForClassic=mm.objid 
INNER JOIN murf_man.job jb ON jb.objid=co.jobId 
INNER JOIN murf_man._order ord ON jb._order=ord.objid 
INNER JOIN murf_man.customer cu ON ord.customer=cu.objid 
INNER JOIN murf_man.ordergroup og ON ord.ordergroup=og.objid 
INNER JOIN murf_csc.corrugator cg ON co.corrugator=cg.objid 
INNER JOIN murf_man.plant pl ON pl.objid=co.plantId 
LEFT JOIN murf_man.specification sp ON sp.objid=ord.masterSpecification 
LEFT JOIN murf_man.materialmaster mm1 ON mm1.objid=co.orderCoatingMasterId 
LEFT JOIN murf_man.materialmaster mm2 ON mm2.objid=co.orderedBoardMasterId 
WHERE (co.corrugatorDueFinishTime>=@startDate and co.corrugatorDueFinishTime<=@FinishDate )
and co.retired=0;
#
SELECT 'RSS WASTE',r.paper_code,r.width,r.unique_roll_id,r.density,r.weight_before_use,r.length_before_use,r.weight_after_use,r.length_after_use,r.roll_status_after,r.start_splice_js,IFNULL(p.density,r.density) 
from murf_map.RSSHST r 
left outer join murf_map.PAPERS p on p.paper_code=r.paper_code 
where r.start_splice_js >= @startDate and r.start_splice_js < @FinishDate
and r.roll_status_after in ("U","W") 
AND r.roll_status_after = 'W'
ORDER BY r.start_splice_js;
#
SELECT 'CSC WASTE',wef.objid,cor.corrugatorNumber,wef.legacyNumber,wer.status,mm.legacyId,wec.rollWidth/254000 rollWidth,wer.createTime,wer.issuedTime,'Y',MOD(wer.sequenceNumber,1000),wer.setupCount,wer.averageTrim/254000 averageTrim,
wec.splitStand,wec.combinationWidth,FLOOR(wer.totalEstimatedLength/254000/12) totalEstimatedLength,wer.totalEstimatedTime,wer.slitterChangeCost,wer.totalRollCost,wer.totalUpgradeCost,wer.totalDowngradeCost,wer.issuedBoardCost,
wer.corrugatorCost,if(wef.legacyNumber<>wer.wetendRunNumber,wer.wetendRunNumber,wer.originalWetendRunNumber),FLOOR(wef.actualLength/254000/12) actualLength,wef.actualTime,wef.startTime,wef.lastSetupEndTime,wef.downTime,
FLOOR(wef.wasteArea/254000) wasteArea,wer.sequenceNumber,wer.starchCost,wer.coatingsCost 
FROM murf_csc.wetendfeedback wef 
STRAIGHT_JOIN murf_csc.wetendrun wer ON wef.wetendRun=wer.objid 
STRAIGHT_JOIN murf_csc.wetendconfiguration wec ON wer.wetendConfiguration=wec.objid 
STRAIGHT_JOIN murf_csc.corrugator cor ON wec.corrugator=cor.objid 
STRAIGHT_JOIN murf_man.materialtype mt ON wec.boardId=mt.objid 
STRAIGHT_JOIN murf_man.materialmaster mm ON mt.master=mm.objid 
WHERE cor.corrugatorNumber=1 and ( (wef.startTime>=@startDate)) and ( (wef.startTime<=@FinishDate)) 
and wef.lastSetupEndTime>0 
order by cor.corrugatorNumber ,wef.startTime;
#