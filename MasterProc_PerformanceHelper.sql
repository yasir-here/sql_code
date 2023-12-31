use [BidModel]
GO

EXEC [ActivateContractors_2023AZTI_ModelRun_PERFORMANCE]
GO




DECLARE
	@BidID int = 28,
	@ModelID int = 71, --All sites: 42, NM: 43
	@ContractorBidList nvarchar(255) = '17,28',	--Comma delimited list, eg '17,18'
	@OverrideCCRName nvarchar(100) = '50''s', --Something like '40''s'
	@IncludeSingleCEIDOutput bit = 1,
	@IncludeMultipleCEIDOutput bit = 1,
	@ExportToReporting bit = 0,
	@OverrideBuilding nvarchar(50) = 'D1X Mod 2',
	@BaseCurrencySymbol nvarchar(50) = '$', --Acceptable values: '$', '€', '₪'
	@TechnologyProcess nvarchar(50) = NULL, --P1274, P1276, or NSG. Can be passed as a comma-delimited list.
	@VarURPSiteID int = 1,
	@ItemCodeMappingSiteID int = 8,
	@UseCodeNames bit = 1,
	@OutputTypeID int = 1,
	@EnforceCodeNames bit = 0,
	@IncludeBuildingAdjustments bit = 1,
	@ModelRunID int


	SET NOCOUNT ON;

	INSERT INTO ModelRun ([InitiatedBy], [OutputTemplate], [BidID], [ModelID])
	VALUES ('SYSTEM', '', @BidID, @ModelID)
	SELECT @ModelRunID = @@IDENTITY

	--TODO: Save parameters to table


	---------- CHECKPOINT ----------
	EXEC RecordEvent @ModelRunID, 'Beginning execution'
	---------- CHECKPOINT ----------












	------------- *************** -------------
	------------- *************** -------------
	-- THIS IS THE APPLES-TO-APPLES PROCEDURE
	IF @IncludeSingleCEIDOutput = 1 OR @IncludeMultipleCEIDOutput = 1 OR @ExportToReporting = 1
		BEGIN
			----------------- RUN THE CONTRACTOR "ACTIVATION" SCRIPT ------------------
			EXEC ActivateDesiredContractors_AllSitesProductivity @ModelID, @ContractorBidList, @ItemCodeMappingSiteID, @TechnologyProcess
			--EXEC ActivateDesiredContractors_WithNullVoid @ModelID
		END


	---------- CHECKPOINT ----------
	EXEC RecordEvent @ModelRunID, 'SOR Activated'
	---------- CHECKPOINT ----------







	------------- *************** -------------
	------------- *************** -------------

	----------------- GET SOME BASIC INFORMATION ABOUT THE MODEL ------------------
	--DECLARE @BidID int
	DECLARE @BidTitle nvarchar(255)
	DECLARE @ModelName varchar(50)
	DECLARE @CCRName nvarchar(100)
	DECLARE @ModelTableName nvarchar(128)
	DECLARE @ReportingTableName nvarchar(128)
	DECLARE @VariableURPAssumptionName varchar(50)
	DECLARE @BidTypeID int

	SELECT
		--@BidID = Model.BidID,
		--@BidTitle = Bids.BidTitle,
		@ModelName = Model.ModelName,
		--@ModelTableName = ModelTableName,
		@ReportingTableName = ReportingTableName,
		@CCRName =
			CASE
				WHEN @OverrideCCRName IS NOT NULL THEN @OverrideCCRName
				ELSE DefaultCCRName
			END,
		@BidTypeID = Bids.BidTypeID
	FROM
		Model
		INNER JOIN Bids ON Model.BidID = Bids.ID
		--INNER JOIN Sites ON Bids.SiteID = Sites.SiteID
	WHERE Model.ID = @ModelID


	/*
	-- Validation
	IF @ExportToReporting = 1 AND @ReportingTableName IS NULL
	BEGIN
		RAISERROR('The @ExportToReporting flag is set to true, but no Reporting table is specified in the Model table.', 18, 0)
		RETURN
	END
	*/
	


	--============================================================
	--================== Get Temp Data ===========================
		
		IF OBJECT_ID('tempdb..#Contractor') IS NOT NULL DROP TABLE #Contractor
		IF OBJECT_ID('tempdb..#SOR') IS NOT NULL DROP TABLE #SOR
		IF OBJECT_ID('tempdb..#CCR') IS NOT NULL DROP TABLE #CCR
		IF OBJECT_ID('tempdb..#TOA') IS NOT NULL DROP TABLE #TOA
		IF OBJECT_ID('tempdb..#Model') IS NOT NULL DROP TABLE #Model
		IF OBJECT_ID('tempdb..#VariableURPOcc') IS NOT NULL DROP TABLE #VariableURPOcc
		IF OBJECT_ID('tempdb..#VariableURP') IS NOT NULL DROP TABLE #VariableURP
		IF OBJECT_ID('tempdb..#ModelWithHidden') IS NOT NULL DROP TABLE #ModelWithHidden
		IF OBJECT_ID('tempdb..#FullModelMapping') IS NOT NULL DROP TABLE #FullModelMapping
		IF OBJECT_ID('tempdb..#FullModelMappingMatch') IS NOT NULL DROP TABLE #FullModelMappingMatch
		IF OBJECT_ID('tempdb..#FullModelMappingNoMatch') IS NOT NULL DROP TABLE #FullModelMappingNoMatch
		IF OBJECT_ID('tempdb..#ModelCEIDMultiplier') IS NOT NULL DROP TABLE #ModelCEIDMultiplier
		IF OBJECT_ID('tempdb..#SingleCEIDOutputData') IS NOT NULL DROP TABLE #SingleCEIDOutputData
		IF OBJECT_ID('tempdb..#MultipleCEIDOutputData') IS NOT NULL DROP TABLE #MultipleCEIDOutputData
		IF OBJECT_ID('tempdb..#CCRMaps') IS NOT NULL DROP TABLE #CCRMaps
		IF OBJECT_ID('tempdb..#BuildingMaps') IS NOT NULL DROP TABLE #BuildingMaps
		IF OBJECT_ID('tempdb..#FAMaps') IS NOT NULL DROP TABLE #FAMaps
		IF OBJECT_ID('tempdb..#URPFAMaps') IS NOT NULL DROP TABLE #URPFAMaps
		IF OBJECT_ID('tempdb..#LevelMaps') IS NOT NULL DROP TABLE #LevelMaps
		IF OBJECT_ID('tempdb..#ScopeDemarcationMaps') IS NOT NULL DROP TABLE #ScopeDemarcationMaps
		IF OBJECT_ID('tempdb..#BuildingLOPMaps') IS NOT NULL DROP TABLE #BuildingLOPMaps
		IF OBJECT_ID('tempdb..#BidIDs') IS NOT NULL DROP TABLE #BidIDs
		IF OBJECT_ID('tempdb..#Techs') IS NOT NULL DROP TABLE #Techs
		IF OBJECT_ID('tempdb..#NoScopeItemCodes') IS NOT NULL DROP TABLE #NoScopeItemCodes
		IF OBJECT_ID('tempdb..#ItemCodeSites') IS NOT NULL DROP TABLE #ItemCodeSites
		IF OBJECT_ID('tempdb..#ItemCodeTradeIDs') IS NOT NULL DROP TABLE #ItemCodeTradeIDs
		IF OBJECT_ID('tempdb..#MappedSOR') IS NOT NULL DROP TABLE #MappedSOR
		IF OBJECT_ID('tempdb..#MappedCCR') IS NOT NULL DROP TABLE #MappedCCR






		------------- *************** -------------
		------------- *************** -------------
		-- GETTING DATA INTO THE TEMP TABLES TO BE USED BY THE MASTER CALCULATION
		------------- *************** -------------
		------------- *************** -------------

		--------- PARAMETER DATA ---------
		SELECT CAST(stringlist as int) as id INTO #BidIDs FROM fn_SplitList(@ContractorBidList, ',') WHERE stringlist <> ''
		SELECT CAST(stringlist as nvarchar(50)) as tech INTO #Techs FROM fn_SplitList(@TechnologyProcess, ',') WHERE stringlist <> ''


		--------- CONTRACTOR DATA ---------
		SELECT
			Contractor.*,
			Trade.ID AS TradeID,
			Currencies.CurrencySymbol,
			Sites.ShortSite AS SiteAbbreviation,
			COALESCE(Contractor.OverrideContractPricingTypeID, Sites.DefaultContractPricingTypeID) AS ContractPricingTypeID,
			CodeNames.CodeName,
			CodeNames.ShortCodeName,
			CASE
				WHEN CodeNames.CodeName IS NOT NULL THEN (Sites.ShortSite + ' ' + CodeNames.CodeName + ' Rev ' + Contractor.OfficialRevisionNumber)
				ELSE Contractor.ContractorName
			END AS FullCodeName
		INTO #Contractor
		FROM
			Contractor
			inner join #BidIDs bids on bids.id = Contractor.BidID
			inner join Trade ON Contractor.Trade = Trade.TradeName
			inner join Sites ON Contractor.SiteID = Sites.SiteID
			left join Currencies on Contractor.CurrencyID = Currencies.ID
			left join ContractorCodeName CodeNames ON
				Contractor.BidID = CodeNames.BidID
				AND Contractor.MasterContractorID = CodeNames.ContractorMasterID
				AND Trade.ID = CodeNames.TradeID
		WHERE Active = 1

		-- Track the contractor submissions we are analyzing with this Model Run
		INSERT INTO [ModelRunSubmissions] ([ModelRunID], [SubmissionID])
		SELECT DISTINCT
			@ModelRunID,
			#Contractor.ID
		FROM
			#Contractor
			
			
		IF @UseCodeNames = 1 AND @EnforceCodeNames = 1
		BEGIN
			IF EXISTS (SELECT 1 FROM #Contractor WHERE CodeName IS NULL OR ShortCodeName IS NULL)
			BEGIN
				RAISERROR('The output is set to use Code Names but there are Active contractors without Code Names assigned.', 18, 0)
				RETURN
			END
		END


		-- Validation
		IF EXISTS
			(
				select 1 from #Contractor where
				(IndirectPCT > 0 AND IndirectPCT < 1)
				OR (BIMPCT > 0 AND BIMPCT < 1)
				OR (AnalyticalTesting > 0 AND AnalyticalTesting < 1)
			)
		BEGIN
			RAISERROR('There are contractor percents that were possibly loaded incorrectly (between 0 and 1 when they should be stated as full percent).', 18, 0)
			RETURN
		END


		--------- TOA DATA ---------
		SELECT TOA.*, #Contractor.SiteID 
			INTO #TOA 
			FROM TOASplit TOA 
			inner join #BidIDs bids ON bids.id = TOA.BidID
			INNER JOIN #Contractor ON TOA.ContractorName = #Contractor.ContractorName AND TOA.BidID = #Contractor.BidID 


		--------- CCR DATA ---------
		SELECT CCR.*, #Contractor.SiteID
			INTO #CCR 
			FROM CCR 
			inner join #BidIDs bids ON bids.id = CCR.BidID
			INNER JOIN #Contractor ON CCR.ContractorName = #Contractor.ContractorName AND CCR.BidID = #Contractor.BidID 


		--------- SOR DATA ---------
		SELECT SOR.* 
			INTO #SOR 
			FROM SOR 
			inner join #BidIDs bids ON bids.id = SOR.BidID
			INNER JOIN #Contractor ON SOR.ContractorName = #Contractor.ContractorName AND SOR.BidID = #Contractor.BidID 

		--select * from #Contractor
		--select * from #TOA
		--SELECT * FROM #CCR
		--select * from #SOR




		--------------- GET OUR MAPPING COMPONENTS ---------------
		SELECT TargetValue+'''s' as TargetValue, SourceSiteID, SourceValue+'''s' as SourceValue
			INTO #CCRMaps 
			FROM [MappingComponents] 
			WHERE MappingType = 'CCR''s' and SourceSiteID in (SELECT DISTINCT SiteID FROM #Contractor)

		SELECT TargetValue, SourceSiteID, SourceValue 
			INTO #BuildingMaps 
			FROM [MappingComponents] 
			WHERE MappingType = 'TOA Building' and SourceSiteID in (SELECT DISTINCT SiteID FROM #Contractor)

		SELECT TargetValue, SourceSiteID, SourceValue 
			INTO #BuildingLOPMaps 
			FROM [MappingComponents] 
			WHERE MappingType = 'URP Fixed LOP' and SourceSiteID in (SELECT DISTINCT SiteID FROM #Contractor)

		SELECT TargetValue, SourceSiteID, SourceValue 
			INTO #FAMaps 
			FROM [MappingComponents] 
			WHERE MappingType = 'FA Adder (Non URP)' and SourceSiteID in (SELECT DISTINCT SiteID FROM #Contractor)

		SELECT TargetValue, SourceSiteID, SourceValue 
			INTO #URPFAMaps 
			FROM [MappingComponents] 
			WHERE MappingType = 'URP FA Adder' and SourceSiteID in (SELECT DISTINCT SiteID FROM #Contractor)

		SELECT TargetValue, SourceSiteID, SourceValue 
			INTO #LevelMaps 
			FROM [MappingComponents] 
			WHERE MappingType = 'TOA Level' and SourceSiteID in (SELECT DISTINCT SiteID FROM #Contractor)

		SELECT TargetValue, SourceSiteID, SourceValue 
			INTO #ScopeDemarcationMaps 
			FROM [MappingComponents] 
			WHERE MappingType = 'TOA Scope demarcation' and SourceSiteID in (SELECT DISTINCT SiteID FROM #Contractor)


		--select * from #CCRMaps
		--select * from #BuildingMaps
		--select * from #BuildingLOPMaps
		--select * from #FAMaps
		--select * from #URPFAMaps
		--select * from #LevelMaps
		--select * from #ScopeDemarcationMaps


		------------------------------------------------
		---------------- MAPPED CCR --------------------
		CREATE TABLE #MappedCCR
		(
			ModelCCRName nvarchar(100),
			BidID int,
			ContractorName nvarchar(100),
			PricedCCRName nvarchar(100),
			PricedTotalCCR money
		)

		-- First populate with a line item for every contractor
		INSERT INTO #MappedCCR (ModelCCRName, BidID, ContractorName)
		select DISTINCT @CCRName, #Contractor.BidID, #Contractor.ContractorName
		from #Contractor

		--select * from #MappedCCR

		-- Now populate pricing for exact matches to the model
		update #MappedCCR
		SET
			PricedCCRName = #CCR.CCRName,
			PricedTotalCCR = #CCR.TotalCCR

		from
			#MappedCCR
			inner join #CCR on #MappedCCR.BidID = #CCR.BidID AND #MappedCCR.ContractorName = #CCR.ContractorName AND #MappedCCR.ModelCCRName = #CCR.CCRName


		-- Now populate pricing for matches to the mappings
		UPDATE #MappedCCR
		SET
			PricedCCRName = #CCR.CCRName,
			PricedTotalCCR = #CCR.TotalCCR
		from
			#MappedCCR
			INNER JOIN #CCRMaps ON
				#MappedCCR.ModelCCRName = #CCRMaps.TargetValue
			INNER JOIN #CCR ON
				#CCR.SiteID = #CCRMaps.SourceSiteID
				AND #CCR.CCRName = #CCRMaps.SourceValue
				AND #MappedCCR.BidID = #CCR.BidID
				AND #MappedCCR.ContractorName = #CCR.ContractorName
		where
			#MappedCCR.PricedCCRName IS NULL


		-- Lastly, get rid of anything in here still not priced
		delete from #MappedCCR where PricedCCRName IS NULL

		--select ModelItemCode, PricedItemCode, COUNT(DISTINCT ContractorName) from #MappedSOR
		--group by ModelItemCode, PricedItemCode
		--order by ModelItemCode

		---------------- MAPPED CCR --------------------
		------------------------------------------------



		---------- CHECKPOINT ----------
		EXEC RecordEvent @ModelRunID, 'First set of temp tables filled'
		---------- CHECKPOINT ----------


		---------------------------------------------------
		------------- ITEM CODE MAPPING -------------------
		CREATE TABLE #FullModelMapping
		(
			ModelSiteID int,
			ModelTradeID int,
			ModelItemCode varchar(100),
			MappedSiteID int,
			MappedTradeID int,
			MappedItemCode varchar(100)
		)

		INSERT INTO #FullModelMapping EXEC GetFullModelMappingTable_AllSitesProductivity @ModelID, @ContractorBidList, @ItemCodeMappingSiteID;
		
		SELECT * INTO #FullModelMappingMatch FROM #FullModelMapping WHERE ModelItemCode = MappedItemCode
		SELECT * INTO #FullModelMappingNoMatch FROM #FullModelMapping WHERE ModelItemCode <> MappedItemCode

		--SELECT * FROM #FullModelMappingMatch
		--SELECT * FROM #FullModelMappingNoMatch

		TRUNCATE TABLE #FullModelMapping



		INSERT INTO #FullModelMapping
		SELECT 
			COALESCE(nm.ModelSiteID,m.ModelSiteID) as ModelSiteID, 
			COALESCE(nm.ModelTradeID,m.ModelTradeID) as ModelTradeID, 
			COALESCE(nm.ModelItemCode,m.ModelItemCode) as ModelItemCode, 
			COALESCE(nm.MappedSiteID,m.MappedSiteID) as MappedSiteID, 
			COALESCE(nm.MappedTradeID,m.MappedTradeID) as MappedTradeID, 
			COALESCE(nm.MappedItemCode,m.MappedItemCode) as MappedItemCode
		FROM #FullModelMappingNoMatch m
		full outer join #FullModelMappingMatch nm on m.ModelItemCode = nm.ModelItemCode 
					and m.ModelSiteID = nm.ModelSiteID 
					and m.ModelTradeID = nm.ModelTradeID 
					and m.MappedSiteID = nm.MappedSiteID 
					and m.MappedTradeID = nm.MappedTradeID



		--SELECT DISTINCT ModelItemCode FROM #FullModelMapping

		--SELECT * FROM #FullModelMapping a
		--inner join #FullModelMapping b on a.MappedItemCode = b.MappedItemCode and a.MappedTradeID = b.MappedTradeID and a.MappedSiteID <> b.MappedSiteID
		--12819


		----------- END ITEM CODE MAPPING -----------------
		---------------------------------------------------


		---------- CHECKPOINT ----------
		EXEC RecordEvent @ModelRunID, 'ItemCode Mapping Done'
		---------- CHECKPOINT ----------


		---------------------------------------------------
		--------------- NO SCOPE LOGIC---------------------
		
		-- Put the No scope item codes into a temp table
		CREATE TABLE #NoScopeItemCodes (ItemCode varchar(100))
		INSERT INTO #NoScopeItemCodes (ItemCode) VALUES ('MISC-0000-0000')
		INSERT INTO #NoScopeItemCodes (ItemCode) VALUES ('No Scope')
		INSERT INTO #NoScopeItemCodes (ItemCode) VALUES ('No Scope2')
		CREATE TABLE #ItemCodeTradeIDs (TradeID int)
		INSERT INTO #ItemCodeTradeIDs (TradeID) VALUES (1)
		INSERT INTO #ItemCodeTradeIDs (TradeID) VALUES (2)
		INSERT INTO #ItemCodeTradeIDs (TradeID) VALUES (3)
		INSERT INTO #ItemCodeTradeIDs (TradeID) VALUES (4)
		CREATE TABLE #ItemCodeSites (SiteID int)
		INSERT INTO #ItemCodeSites select DISTINCT ItemCodeMappingSiteID from #Contractor

		-- Unhide SOR items that may have been hidden by the Activation script
		UPDATE #SOR SET Hide = 0 WHERE ItemCode IN (select ItemCode from #NoScopeItemCodes)
		-- Unhide MODEL items that may have been hidden by the Activation script
		UPDATE ModelBOQDetails SET Hide = 0 WHERE
			ItemCode IN (select ItemCode from #NoScopeItemCodes)
			AND ModelID = @ModelID
			and TechnologyProcess in (SELECT tech from #Techs)


		-- Remove any existing item code mappings (probably don't exist anywat)
		delete from #FullModelMapping where ModelItemCode IN (select ItemCode from #NoScopeItemCodes)

		--select * from #FullModelMapping order by ModelItemCode
		-- Populate #FullModelMapping with fake-mapped records for all
		-- Sites/Trades/ItemCodes
		INSERT INTO #FullModelMapping
		select * from
			(select @ItemCodeMappingSiteID AS ModelSiteID) A
			inner join (select DISTINCT TradeID from #ItemCodeTradeIDs) B on 1=1
			inner join (select DISTINCT ItemCode from #NoScopeItemCodes) C on 1=1
			inner join (select DISTINCT SiteID from #ItemCodeSites) D on 1=1
			inner join (select DISTINCT TradeID from #ItemCodeTradeIDs) E on B.TradeID = E.TradeID
			inner join (select DISTINCT ItemCode from #NoScopeItemCodes) F on C.ItemCode = F.ItemCode


		-- Now put fake records into #SOR for no cost items
		--select * from #SOR where ItemCode IN (select ItemCode from #NoScopeItemCodes) 
		INSERT INTO #SOR (ID, BidID, ContractorName, ItemCode, Spec, Specification, Classification, Size, Unit, Labor, TotalMaterial, hide, hideDemo, CreateTimestamp, IsNullVoid, IsDuplicated, HasInconsistentUnits)
		SELECT
			(SELECT MAX (ID) FROM #SOR) + ROW_NUMBER() OVER(ORDER BY AllPotentialItemCodes.ContractorName ASC),
			AllPotentialItemCodes.BidID,
			AllPotentialItemCodes.ContractorName,
			AllPotentialItemCodes.ItemCode,
			'No Scope',
			'No Scope',
			'No Scope',
			'No Scope',
			'EA',
			0,
			0,
			0,
			0,
			getdate(),
			1,
			0,
			0
		FROM
			(SELECT DISTINCT BidID, ContractorName, ItemCode FROM #Contractor INNER JOIN #NoScopeItemCodes ON 1=1) AllPotentialItemCodes
			LEFT JOIN (select DISTINCT BidID, ContractorName, ItemCode from #SOR WHERE ItemCode IN (select ItemCode from #NoScopeItemCodes)) ExistingNoScopeBids
				ON
					AllPotentialItemCodes.BidID = ExistingNoScopeBids.BidID
					AND AllPotentialItemCodes.ContractorName = ExistingNoScopeBids.ContractorName
					AND AllPotentialItemCodes.ItemCode = ExistingNoScopeBids.ItemCode
		WHERE ExistingNoScopeBids.ItemCode IS NULL

		------------- END NO SCOPE LOGIC-------------------
		---------------------------------------------------



		--================== Temp table of CEID Multipliers ===========================
		-- We get ALL CEID's from the model...and then join the mutiplier.  And if there's no match, a
		-- quantity of 1 is assumed
		CREATE TABLE #ModelCEIDMultiplier
		(
			Trade varchar(100),
			CEID varchar(25),
			TechnologyProcess varchar(25),
			Quantity int
		)
		--declare @tempMultiplierSQL varchar(max)
		--set @tempMultiplierSQL = 
		INSERT INTO #ModelCEIDMultiplier (Trade, CEID, TechnologyProcess, Quantity)
		SELECT DISTINCT
			MODEL.Trade,
			MODEL.CEID,
			MODEL.TechnologyProcess,
			ISNULL(MCM.Quantity, 1) AS CEIDCount
		FROM
			ModelBOQDetails MODEL
			LEFT OUTER JOIN (SELECT * FROM ModelBOQ where ModelID = @ModelID) MCM ON
				MODEL.Trade = MCM.Trade
				AND MODEL.CEID = MCM.CEID
				AND
				(
					(@TechnologyProcess is null)
					OR
					(MODEL.TechnologyProcess = MCM.TechnologyProcess)
				)
		WHERE MODEL.ModelID = @ModelID

		--exec (@tempMultiplierSQL)



		--================== Temp table of the model ===========================
		-- Get our model quantities grouped
		CREATE TABLE #ModelWithHidden
		(
			SiteID int,
			CEID varchar(25),
			Building varchar(50),
			FunctionalArea varchar(25),
			CostCode varchar(50),
			Quantity numeric(10,2),
			Location varchar(100),
			ItemCode varchar(100),
			Trade varchar(100),
			TradeID int,
			ScopeDemarcation varchar(25),
			Unit varchar(50),
			TechnologyProcess varchar(25),
			Size varchar(250),
			Classification varchar(500),
			Spec varchar(100),
			Specification varchar(100),
			--Service varchar(100),-- RICK
			Hide bit
		)

		INSERT INTO #ModelWithHidden
		(
			SiteID,
			CEID,
			Building,
			FunctionalArea,
			CostCode,
			Quantity,
			Location,
			ItemCode,
			Trade,
			TradeID,
			ScopeDemarcation,
			Unit,
			TechnologyProcess,
			Size,
			Classification,
			Spec,
			Specification,
			--Service,-- RICK
			Hide
		)
		SELECT
			CAST(@ItemCodeMappingSiteID AS varchar(10)),
			CEID,
			Building,
			FunctionalArea,
			CostCode,
			Quantity,
			Location,
			ItemCode,
			Trade,
			Trade.ID,
			ScopeDemarcation,
			Unit,
			TechnologyProcess,
			Size,
			Classification,
			Spec,
			Specification,
			--Service,-- RICK
			Hide
		FROM
			ModelBOQDetails
			inner join Trade on ModelBOQDetails.Trade = Trade.TradeName
		WHERE ModelID = @ModelID and (@TechnologyProcess is null or TechnologyProcess in (SELECT tech from #Techs))

		--SELECT * FROM #ModelWithHidden

		IF @OverrideBuilding is not null
		BEGIN
			UPDATE #ModelWithHidden SET Building = @OverrideBuilding
		END
		
		
		select * into #Model
		from #ModelWithHidden where Hide <> 1
			   


		SELECT FA, Discipline, SORItemFactor, PctOccurrence INTO #VariableURPOcc FROM VarURPOccurrence WHERE ModelID = @ModelID and SiteID = @VarURPSiteID
		SELECT @VariableURPAssumptionName = ShortSite from Sites where SiteID = @VarURPSiteID
		

		SELECT c.ContractorName, vurpo.FA, vurpo.Discipline, SUM(vurpo.PctOccurrence*(toa.LaborAdjust-1)) as VariableURPAdder 
			INTO #VariableURP
			FROM #Contractor c
			inner join #VariableURPOcc vurpo on vurpo.Discipline = c.Trade
			inner join #TOA toa on toa.AdjustmentType = 'VariableAdder'
				AND toa.AdjustmentName = vurpo.SORItemFactor
				AND toa.ContractorName = c.ContractorName
				AND toa.BidID = c.BidID
			GROUP BY c.ContractorName, vurpo.FA, vurpo.Discipline

		--SELECT * FROM #VariableURP

		--SELECT * FROM #TOA WHERE AdjustmentType = 'VariableAdder'

		--SELECT * FROM #Model


		---------- CHECKPOINT ----------
		EXEC RecordEvent @ModelRunID, 'Model TEMP Tables filled'
		---------- CHECKPOINT ----------


		------------------------------------------------
		---------------- MAPPED SOR --------------------
		CREATE TABLE #MappedSOR
		(
			ModelItemCode varchar(100),
			ModelTradeID int,
			ModelSiteID int,
			BidID int,
			ContractorName nvarchar(100),
			PricedItemCode varchar(50),
			PricedSpec varchar(100),
			PricedClassification varchar(500),
			PricedSize varchar(250),
			PricedUnit varchar(50),
			PricedLabor float,
			PricedMaterial money
		)

		-- First populate with a line item for every contractor for every model line item (SOR Details omitted for now)
		INSERT INTO #MappedSOR (ModelItemCode, ModelTradeID, ModelSiteID, BidID, ContractorName)
		select DISTINCT #ModelWithHidden.ItemCode, #ModelWithHidden.TradeID, #ModelWithHidden.SiteID, #Contractor.BidID, #Contractor.ContractorName
		from
			#ModelWithHidden
			inner join #Contractor on #ModelWithHidden.TradeID = #Contractor.TradeID

		--select ModelItemCode, PricedItemCode, COUNT(DISTINCT ContractorName) from #MappedSOR
		--group by ModelItemCode, PricedItemCode
		--order by ModelItemCode

		-- Now populate pricing for exact matches to the model
		update #MappedSOR
		SET
			PricedItemCode = #SOR.ItemCode,
			PricedSpec = #SOR.Spec,
			PricedClassification = #SOR.Classification,
			PricedSize = #SOR.Size,
			PricedUnit = #SOR.Unit,
			PricedLabor = #SOR.Labor,
			PricedMaterial = #SOR.TotalMaterial
		from
			#MappedSOR
			inner join #SOR on #MappedSOR.BidID = #SOR.BidID AND #MappedSOR.ContractorName = #SOR.ContractorName AND #MappedSOR.ModelItemCode = #SOR.ItemCode
		where #SOR.hide <> 1

		--	select ModelItemCode, PricedItemCode, COUNT(DISTINCT ContractorName) from #MappedSOR
		--group by ModelItemCode, PricedItemCode
		--order by ModelItemCode
	
		-- Now populate pricing for matches to the mappings
		UPDATE #MappedSOR
		SET
			PricedItemCode = #SOR.ItemCode,
			PricedSpec = #SOR.Spec,
			PricedClassification = #SOR.Classification,
			PricedSize = #SOR.Size,
			PricedUnit = #SOR.Unit,
			PricedLabor = #SOR.Labor,
			PricedMaterial = #SOR.TotalMaterial
		from
			#MappedSOR
			INNER JOIN #FullModelMapping ON
				#MappedSOR.ModelTradeID = #FullModelMapping.ModelTradeID
				AND #MappedSOR.ModelItemCode = #FullModelMapping.ModelItemCode
				AND #MappedSOR.ModelSiteID = #FullModelMapping.ModelSiteID
			INNER JOIN #SOR ON
				#SOR.ItemCode = #FullModelMapping.MappedItemCode
				AND #SOR.ContractorName = #MappedSOR.ContractorName
				AND #SOR.BidID = #MappedSOR.BidID
			INNER JOIN #Contractor AS c ON
				c.ContractorName = #MappedSOR.ContractorName
				AND C.BidID = #MappedSOR.BidID
				AND C.TradeID = #FullModelMapping.MappedTradeID
				AND C.ItemCodeMappingSiteID = #FullModelMapping.MappedSiteID
		where
			#MappedSOR.PricedItemCode IS NULL
			AND #SOR.hide <> 1

		--select ModelItemCode, PricedItemCode, COUNT(DISTINCT ContractorName) from #MappedSOR
		--group by ModelItemCode, PricedItemCode
		--order by ModelItemCode

		--select ModelItemCode, PricedItemCode, COUNT(DISTINCT ContractorName) from #MappedSOR
		--group by ModelItemCode, PricedItemCode
		--having
		--	(COUNT(DISTINCT ContractorName) <> 3)
		--	OR
		--	(PricedItemCode IS NULL AND COUNT(DISTINCT ContractorName) = 3)
		--order by ModelItemCode

		-- Lastly, get rid of anything in here still not priced
		delete from #MappedSOR where PricedItemCode IS NULL

		--select ModelItemCode, PricedItemCode, COUNT(DISTINCT ContractorName) from #MappedSOR
		--group by ModelItemCode, PricedItemCode
		--order by ModelItemCode

		---------------- MAPPED SOR --------------------
		------------------------------------------------


		---------- CHECKPOINT ----------
		EXEC RecordEvent @ModelRunID, 'SOR Mapping Done'
		---------- CHECKPOINT ----------


		------------------------------------------------
		------------ FILL MAPPED TOA's   ---------------

		-- We're going to fill in this mapping table with "equivalent" mappings if there
		-- are none defined
		INSERT INTO #ScopeDemarcationMaps (TargetValue, SourceSiteID, SourceValue)
		(
			SELECT AllCombinations.ScopeDemarcation, AllCombinations.SiteID, AllCombinations.ScopeDemarcation FROM
				(
					SELECT * FROM
						(SELECT DISTINCT ScopeDemarcation from #Model WHERE ScopeDemarcation IS NOT NULL) SD
						JOIN (SELECT DISTINCT SiteID FROM #Contractor) C ON 1=1
				) AllCombinations
				LEFT JOIN #ScopeDemarcationMaps SDM ON
					AllCombinations.ScopeDemarcation = SDM.TargetValue
					AND AllCombinations.SiteID = SDM.SourceSiteID
			WHERE SDM.TargetValue IS NULL
		)

		INSERT INTO #LevelMaps (TargetValue, SourceSiteID, SourceValue)
		(
			SELECT AllCombinations.Location, AllCombinations.SiteID, AllCombinations.Location FROM
				(
					SELECT * FROM
						(SELECT DISTINCT Location from #Model WHERE Location IS NOT NULL) SD
						JOIN (SELECT DISTINCT SiteID FROM #Contractor) C ON 1=1
				) AllCombinations
				LEFT JOIN #LevelMaps SDM ON
					AllCombinations.Location = SDM.TargetValue
					AND AllCombinations.SiteID = SDM.SourceSiteID
			WHERE SDM.TargetValue IS NULL
		)

		INSERT INTO #BuildingMaps (TargetValue, SourceSiteID, SourceValue)
		(
			SELECT AllCombinations.Building, AllCombinations.SiteID, AllCombinations.Building FROM
				(
					SELECT * FROM
						(SELECT DISTINCT Building from #Model WHERE Building IS NOT NULL) SD
						JOIN (SELECT DISTINCT SiteID FROM #Contractor) C ON 1=1
				) AllCombinations
				LEFT JOIN #BuildingMaps SDM ON
					AllCombinations.Building = SDM.TargetValue
					AND AllCombinations.SiteID = SDM.SourceSiteID
			WHERE SDM.TargetValue IS NULL
		)

		INSERT INTO #BuildingLOPMaps (TargetValue, SourceSiteID, SourceValue)
		(
			SELECT AllCombinations.Building, AllCombinations.SiteID, AllCombinations.Building FROM
				(
					SELECT * FROM
						(SELECT DISTINCT Building from #Model WHERE Building IS NOT NULL) SD
						JOIN (SELECT DISTINCT SiteID FROM #Contractor) C ON 1=1
				) AllCombinations
				LEFT JOIN #BuildingLOPMaps SDM ON
					AllCombinations.Building = SDM.TargetValue
					AND AllCombinations.SiteID = SDM.SourceSiteID
			WHERE SDM.TargetValue IS NULL
		)

		INSERT INTO #URPFAMaps (TargetValue, SourceSiteID, SourceValue)
		(
			SELECT AllCombinations.FunctionalArea, AllCombinations.SiteID, AllCombinations.FunctionalArea FROM
				(
					SELECT * FROM
						(SELECT DISTINCT FunctionalArea from #Model WHERE FunctionalArea IS NOT NULL) SD
						JOIN (SELECT DISTINCT SiteID FROM #Contractor) C ON 1=1
				) AllCombinations
				LEFT JOIN #URPFAMaps SDM ON
					AllCombinations.FunctionalArea = SDM.TargetValue
					AND AllCombinations.SiteID = SDM.SourceSiteID
			WHERE SDM.TargetValue IS NULL
		)

		INSERT INTO #FAMaps (TargetValue, SourceSiteID, SourceValue)
		(
			SELECT AllCombinations.FunctionalArea, AllCombinations.SiteID, AllCombinations.FunctionalArea FROM
				(
					SELECT * FROM
						(SELECT DISTINCT FunctionalArea from #Model WHERE FunctionalArea IS NOT NULL) SD
						JOIN (SELECT DISTINCT SiteID FROM #Contractor) C ON 1=1
				) AllCombinations
				LEFT JOIN #FAMaps SDM ON
					AllCombinations.FunctionalArea = SDM.TargetValue
					AND AllCombinations.SiteID = SDM.SourceSiteID
			WHERE SDM.TargetValue IS NULL
		)




		--SELECT * FROM #Model
		--SELECT SUM(Quantity) as Quantity, SiteID, Trade FROM #Model
		--GROUP BY SiteID, Trade
		--SELECT * FROM #VariableURP

		--SELECT * FROM #TOA WHERE AdjustmentType = 'Location'

		--SELECT * FROM #FullModelMapping
		--WHERE ModelItemCode = '11AI-0170-0150'

		--SELECT * FROM #Model
		--ORDER BY ItemCode
		










		------------- *************** -------------
		------------- *************** -------------
		-- MASTER CALCULATION...SINGLE, THEN MULTIPLE
		------------- *************** -------------
		------------- *************** -------------


		---------- CHECKPOINT ----------
		EXEC RecordEvent @ModelRunID, 'Beginning Master Calculation'
		---------- CHECKPOINT ----------


		IF @IncludeSingleCEIDOutput = 1 OR @IncludeMultipleCEIDOutput = 1 OR @ExportToReporting = 1
			BEGIN
				---------------------------------------------
				---------- SINGLE CEID TEMP OUTPUT ----------
				---------------------------------------------
				SELECT  --*--TOAFunctionalArea.*, TOAURPFA.*, BuildingLOP.*
					c.BidID
					,CASE
						WHEN @UseCodeNames = 0 THEN c.contractorname
						WHEN @UseCodeNames = 1 AND @EnforceCodeNames = 1 THEN FullCodeName
						WHEN @UseCodeNames = 1 AND @EnforceCodeNames = 0 THEN COALESCE(FullCodeName, c.contractorname)
					END AS Contractor
					,c.Trade AS Trade
					,MODEL.TradeID
					,CASE
						WHEN @UseCodeNames = 0 THEN c.Shortname
						WHEN @UseCodeNames = 1 AND @EnforceCodeNames = 1 THEN c.ShortCodeName
						WHEN @UseCodeNames = 1 AND @EnforceCodeNames = 0 THEN COALESCE(c.ShortCodeName, c.Shortname)
					END AS Shortname
					,c.SiteAbbreviation
					,c.OfficialRevisionNumber
					,CASE
						WHEN @UseCodeNames = 0 THEN c.Shortname + ' Rev ' + c.OfficialRevisionNumber
						WHEN @UseCodeNames = 1 AND @EnforceCodeNames = 1 THEN c.ShortCodeName + ' Rev ' + c.OfficialRevisionNumber
						WHEN @UseCodeNames = 1 AND @EnforceCodeNames = 0 THEN COALESCE(c.ShortCodeName + ' Rev ' + c.OfficialRevisionNumber, c.Shortname + ' Rev ' + c.OfficialRevisionNumber)
					END AS FriendlyRevName
					,'Rev ' + c.OfficialRevisionNumber AS ShortRevName
					,c.IsMarket
					,c.IsLastPricePaid
					,c.IsTarget
					,c.IsIPD
					,c.ContractorTypeVersion
					,c.CreateTimestamp AS RevImportTimestamp
					,c.TotalCostDiscountPCT
					,MODEL.CEID
					,MODEL.TechnologyProcess
					,MODEL.FunctionalArea
					,MODEL.ScopeDemarcation
					,1 AS CEIDCount
					,MODEL.CostCode as CostCode
					,MODEL.ItemCode AS ModelItemCode
					,SOR.PricedItemCode AS ItemCode
					,MODEL.Size AS ModelSize
					,SOR.PricedSize AS Size
					,ISNULL(MODEL.Classification, '') AS ModelClassification
					,ISNULL(SOR.PricedClassification, '') AS Classification
					,MODEL.Unit AS ModelUnit
					,SOR.PricedUnit AS Unit
					,MODEL.Spec AS ModelSpec
					,SOR.PricedSpec AS Spec
					,MODEL.Specification AS ModelSpecification
					--,MODEL.Service -- RICK
					,SOR.PricedLabor AS UnconvertedBaseLaborInSOR
					,dbo.GetConvertedRate(SOR.PricedUnit, Model.Unit, SOR.PricedLabor) AS BaseLaborinSOR
					,(c.CurrencySymbol + (CAST(SOR.PricedMaterial AS varchar(20)))) AS UnconvertedBaseMaterialRate
					,dbo.GetConvertedRate(c.CurrencySymbol, @BaseCurrencySymbol, dbo.GetConvertedRate(SOR.PricedUnit, Model.Unit, SOR.PricedMaterial)) AS BaseMaterialRate
					,MODEL.Quantity AS BOQQty
					,BaseHours.StandardHours
					,CASE c.ContractPricingTypeID
						WHEN 1 THEN 0
						WHEN 3 THEN 0
						WHEN 2 THEN HoursComponents.BuildingTOAHours
						ELSE 0
					END AS BuildingTOAHours
					,CASE c.ContractPricingTypeID
						WHEN 1 THEN 0
						WHEN 3 THEN 0
						WHEN 2 THEN HoursComponents.LocationTOAHours
						ELSE 0
					END AS LocationTOAHours
					,CASE c.ContractPricingTypeID
						WHEN 1 THEN 0
						WHEN 3 THEN 0
						WHEN 2 THEN HoursComponents.FunctionalAreaTOAHours
						ELSE 0
					END AS FunctionalAreaTOAHours
					,CASE c.ContractPricingTypeID
						WHEN 1 THEN 0
						WHEN 3 THEN 0
						WHEN 2 THEN HoursComponents.ScopeDemarcationTOAHours
						ELSE 0
					END AS ScopeDemarcationTOAHours
					,CASE c.ContractPricingTypeID
						WHEN 1 THEN 0
						WHEN 3 THEN 0
						WHEN 2 THEN NonURPHours.TotalHoursNonURP
						ELSE 0
					END AS TotalHoursNonURP
					,CostComponents.LaborCost
					,CostComponents.MaterialCost
					,ExpandedCostComponents.LaborAndMaterial
					,ExpandedCostComponents.IndirectCost
					,ExpandedCostComponents.BIMCost
					,ExpandedCostComponents.AnalyticalTestingCost
					--,(ExpandedCostComponents.LaborAndMaterial + ExpandedCostComponents.IndirectCost + ExpandedCostComponents.BIMCost + ExpandedCostComponents.AnalyticalTestingCost) AS TotalCost
					,TotalCostCalc.TotalCost
					,TotalCostDiscountCalc.TotalCostDiscount
					,DiscountedTotalCostCalc.DiscountedTotalCost
					,MODEL.Location
					--,SOR.hide
					--,SOR.IsNullVoid
					,dbo.GetConvertedRate(c.CurrencySymbol, @BaseCurrencySymbol, CCR.PricedTotalCCR) AS TotalCCR
					,BIMHours
					,CASE c.ContractPricingTypeID
						WHEN 1 THEN StandardHoursURP
						WHEN 2 THEN 0
						WHEN 3 THEN 0
						ELSE 0
					END AS StandardHoursURP
					,CASE c.ContractPricingTypeID
						WHEN 1 THEN FAURP
						WHEN 2 THEN 0
						WHEN 3 THEN 0
						ELSE 0
					END AS FAURP
					,CASE c.ContractPricingTypeID
						WHEN 1 THEN LOPURP
						WHEN 2 THEN 0
						WHEN 3 THEN 0
						ELSE 0
					END AS LOPURP
					,CASE c.ContractPricingTypeID
						WHEN 1 THEN VariableURP
						WHEN 2 THEN 0
						WHEN 3 THEN 0
						ELSE 0
					END AS VariableURP
					,CASE c.ContractPricingTypeID
						WHEN 1 THEN FixedURP
						WHEN 2 THEN 0
						WHEN 3 THEN 0
						ELSE 0
					END AS FixedURP
					,CASE c.ContractPricingTypeID
						WHEN 1 THEN URPHours.TotalHoursURP
						WHEN 2 THEN 0
						WHEN 3 THEN 0
						ELSE 0
					END AS TotalHoursURP
					,TotalHoursWithoutBIM
					,DetailingHours
					,TotalHoursWithBIM
					,(ISNULL(c.IndirectPCT, 0)/100) AS IndirectPCT
				INTO #SingleCEIDOutputData
				FROM #Model MODEL
					INNER JOIN #MappedSOR SOR ON
						MODEL.TradeID = SOR.ModelTradeID
						AND MODEL.ItemCode = SOR.ModelItemCode
						AND MODEL.SiteID = SOR.ModelSiteID
					INNER JOIN #Contractor AS c ON
						c.ContractorName = SOR.ContractorName
						AND C.BidID = SOR.BidID
					INNER JOIN #MappedCCR CCR ON
						CCR.ContractorName = c.ContractorName
						AND CCR.BidID = c.BidID
					LEFT JOIN
						(
							select
								#TOA.BidID, #TOA.ContractorName, #TOA.AdjustmentType, #TOA.AdjustmentName, IIF(@IncludeBuildingAdjustments = 1, #TOA.LaborAdjust, 1) AS LaborAdjust, #TOA.MaterialAdjust, #TOA.SiteID,
								#BuildingMaps.TargetValue AS BuildingToMatch
							FROM
								#TOA
								INNER JOIN #BuildingMaps ON #TOA.SiteID = #BuildingMaps.SourceSiteID AND #TOA.AdjustmentName = #BuildingMaps.SourceValue
							WHERE #TOA.AdjustmentType = 'Area'
						) TOABuilding ON
							TOABuilding.BuildingToMatch = MODEL.Building
							AND TOABuilding.ContractorName = c.ContractorName
							AND TOABuilding.BidID = c.BidID
					LEFT JOIN
						(
							select
								#TOA.BidID, #TOA.ContractorName, #TOA.AdjustmentType, #TOA.AdjustmentName, #TOA.LaborAdjust, #TOA.MaterialAdjust, #TOA.SiteID,
								#LevelMaps.TargetValue AS LocationToMatch
							FROM
								#TOA
								INNER JOIN #LevelMaps ON #TOA.SiteID = #LevelMaps.SourceSiteID AND #TOA.AdjustmentName = #LevelMaps.SourceValue
							WHERE #TOA.AdjustmentType = 'Location'

							UNION

							select
								#TOA.BidID, #TOA.ContractorName, #TOA.AdjustmentType, #TOA.AdjustmentName + ' Labor Only' AS AdjustmentName, #TOA.LaborAdjust, 0, #TOA.SiteID,
								#LevelMaps.TargetValue + ' Labor Only' AS LocationToMatch
							FROM
								#TOA
								INNER JOIN #LevelMaps ON #TOA.SiteID = #LevelMaps.SourceSiteID AND #TOA.AdjustmentName = #LevelMaps.SourceValue
							WHERE #TOA.AdjustmentType = 'Location'
						) TOALocation ON
							/* POTENTIAL "Exact Match (without mapping)
							(
								(TOALocation.LocationToMatch = MODEL.Location)
								OR
								(TOALocation.AdjustmentName = MODEL.Location)
							)
							*/
							TOALocation.LocationToMatch = MODEL.Location
							AND TOALocation.ContractorName = c.ContractorName
							AND TOALocation.BidID = c.BidID
					LEFT JOIN
						(
							select
								#TOA.BidID, #TOA.ContractorName, #TOA.AdjustmentType, #TOA.AdjustmentName, #TOA.LaborAdjust, #TOA.MaterialAdjust, #TOA.SiteID,
								#ScopeDemarcationMaps.TargetValue AS ScopeDemarcationToMatch
							FROM
								#TOA
								INNER JOIN #ScopeDemarcationMaps ON #TOA.SiteID = #ScopeDemarcationMaps.SourceSiteID AND #TOA.AdjustmentName = #ScopeDemarcationMaps.SourceValue
							WHERE #TOA.AdjustmentType = 'ScopeDemarcation'
						) TOAScopeDemarcation ON
							TOAScopeDemarcation.ScopeDemarcationToMatch = MODEL.ScopeDemarcation
							AND TOAScopeDemarcation.ContractorName = c.ContractorName
							AND TOAScopeDemarcation.BidID = c.BidID
					LEFT JOIN
						(
							select
								#TOA.BidID, #TOA.ContractorName, #TOA.AdjustmentType, #TOA.AdjustmentName, #TOA.LaborAdjust, #TOA.MaterialAdjust, #TOA.SiteID,
								#FAMaps.TargetValue AS FAToMatch
							FROM
								#TOA
								INNER JOIN #FAMaps ON #TOA.SiteID = #FAMaps.SourceSiteID AND #TOA.AdjustmentName = #FAMaps.SourceValue
							WHERE #TOA.AdjustmentType = 'FunctionalArea'
						) TOAFunctionalArea ON
							TOAFunctionalArea.FAToMatch = MODEL.FunctionalArea
							AND TOAFunctionalArea.ContractorName = c.ContractorName
							AND TOAFunctionalArea.BidID = c.BidID
					LEFT JOIN
						(
							select
								#TOA.BidID, #TOA.ContractorName, #TOA.AdjustmentType, #TOA.AdjustmentName, #TOA.LaborAdjust, #TOA.MaterialAdjust, #TOA.SiteID,
								#URPFAMaps.TargetValue AS URPFAToMatch
							FROM
								#TOA
								INNER JOIN #URPFAMaps ON #TOA.SiteID = #URPFAMaps.SourceSiteID AND #TOA.AdjustmentName = #URPFAMaps.SourceValue
							WHERE #TOA.AdjustmentType = 'URP FA'
						) TOAURPFA ON
							TOAURPFA.URPFAToMatch = MODEL.FunctionalArea
							AND TOAURPFA.ContractorName = c.ContractorName
							AND TOAURPFA.BidID = c.BidID
					LEFT JOIN
						(
							select
								#TOA.BidID, #TOA.ContractorName, #TOA.AdjustmentType, #TOA.AdjustmentName, IIF(@IncludeBuildingAdjustments = 1, #TOA.LaborAdjust, 1) AS LaborAdjust, #TOA.MaterialAdjust, #TOA.SiteID,
								#BuildingLOPMaps.TargetValue AS BuildingLOPToMatch
							FROM
								#TOA
								INNER JOIN #BuildingLOPMaps ON #TOA.SiteID = #BuildingLOPMaps.SourceSiteID AND #TOA.AdjustmentName = #BuildingLOPMaps.SourceValue
							WHERE #TOA.AdjustmentType = 'BuildingLOP'
						) BuildingLOP ON
							BuildingLOP.BuildingLOPToMatch = MODEL.Building
							AND BuildingLOP.ContractorName = c.ContractorName
							AND BuildingLOP.BidID = c.BidID
					LEFT JOIN #VariableURP VarURP ON
						VarURP.ContractorName = c.ContractorName
						AND VarURP.Discipline = c.Trade
						AND VarURP.FA = MODEL.FunctionalArea
					CROSS APPLY
					(
						SELECT
							(MODEL.Quantity * dbo.GetConvertedRate(SOR.PricedUnit, Model.Unit, SOR.PricedLabor)) AS StandardHours
					) AS BaseHours
					CROSS APPLY
					(
						SELECT
						(
							BaseHours.StandardHours
							* (ISNULL(TOABuilding.LaborAdjust, 1))
							* (ISNULL(TOALocation.LaborAdjust, 1))
							* (ISNULL(TOAScopeDemarcation.LaborAdjust, 1))
						) AS TotalAdjustedHoursCompositeTOA
					) AS CompositeTOAHours
					CROSS APPLY
					(
						SELECT
							(BaseHours.StandardHours * (ISNULL(TOABuilding.LaborAdjust, 1)-1)) AS BuildingTOAHours,
							(BaseHours.StandardHours * (ISNULL(TOALocation.LaborAdjust, 1)-1)) AS LocationTOAHours,
							CASE
								WHEN c.FunctionalAreaCalculationMethodID = 1 THEN
									-- Base Hours Only
									(BaseHours.StandardHours * (ISNULL(TOAFunctionalArea.LaborAdjust, 1)-1))
								WHEN c.FunctionalAreaCalculationMethodID = 2 THEN
									-- Base Hours and Building Modifier
									((BaseHours.StandardHours) * (ISNULL(TOABuilding.LaborAdjust, 1) * (ISNULL(TOAFunctionalArea.LaborAdjust, 1))-1))
								ELSE
									-- Base Hours Only
									(BaseHours.StandardHours * (ISNULL(TOAFunctionalArea.LaborAdjust, 1)-1))
							END AS FunctionalAreaTOAHours,
							(BaseHours.StandardHours * (ISNULL(TOAScopeDemarcation.LaborAdjust, 1)-1)) AS ScopeDemarcationTOAHours
					) AS HoursComponents
					CROSS APPLY
					(
						SELECT
						(
							BaseHours.StandardHours
							+ HoursComponents.BuildingTOAHours
							+ HoursComponents.LocationTOAHours
							+ HoursComponents.FunctionalAreaTOAHours
							+ HoursComponents.ScopeDemarcationTOAHours
						) AS TotalHoursNonURP
					) AS NonURPHours
					CROSS APPLY
					(
						SELECT (NonURPHours.TotalHoursNonURP * (ISNULL(c.BIMPCT, 0)/100)) AS BIMHours
					) AS BIMHoursComponent
					CROSS APPLY
					(
						SELECT (BaseHours.StandardHours * (ISNULL(c.DetailingPCT, 0)/100)) AS DetailingHours
					) AS DetailingHoursComponent
					CROSS APPLY
					(
						SELECT
						(
							-- StandardHours * (BuildingTOA*FAURPTOA*ScopeDemarcationTOA - 1)
							--(BuildingTOAHours+ScopeTOAHours) * (BuildingLOP-1)
							(BaseHours.StandardHours * ISNULL(TOABuilding.LaborAdjust, 1) * (ISNULL(TOAURPFA.LaborAdjust, 1) - 1))
						) as FAURP,
						(
							-- StandardHours * (BuildingTOA*ScopeDemarcationTOA*BuildingLOP - 1)
							--(BuildingTOAHours+ScopeTOAHours) * (BuildingLOP-1)
							(BaseHours.StandardHours * ISNULL(TOABuilding.LaborAdjust, 1) * (ISNULL(BuildingLOP.LaborAdjust, 1) - 1))
						) as LOPURP
					) as URPSubComponents
					CROSS APPLY
					(
						SELECT
							(BaseHours.StandardHours * ISNULL(TOABuilding.LaborAdjust, 1) * ISNULL(TOALocation.LaborAdjust, 1) * ISNULL(TOAScopeDemarcation.LaborAdjust, 1)) AS StandardHoursURP,
							(ISNULL(URPSubComponents.FAURP, 0) + ISNULL(URPSubComponents.LOPURP, 0)) as FixedURP,
							(
								-- StandardHours * (ScopeDemarcationTOA*BuildingTOA*VariableURP - 1) 
								(BaseHours.StandardHours * ISNULL(TOABuilding.LaborAdjust, 1) * (ISNULL(VarURP.VariableURPAdder+1, 1) - 1))
							) as VariableURP
					) as URPComponents
					CROSS APPLY
					(
						SELECT
							/*
							(ISNULL(URPComponents.FixedURP, 0) + ISNULL(URPComponents.VariableURP, 0)) AS TotalHoursURP,
							(ISNULL(BaseHours.StandardHours, 0) + ISNULL(HoursComponents.BuildingTOAHours, 0) + ISNULL(HoursComponents.LocationTOAHours, 0) + ISNULL(HoursComponents.FunctionalAreaTOAHours, 0) + ISNULL(HoursComponents.ScopeDemarcationTOAHours, 0)) AS TotalHoursNonURP
							*/
							(
								URPComponents.StandardHoursURP +
								URPComponents.FixedURP +
								URPComponents.VariableURP
							) AS TotalHoursURP
					) AS URPHours
					CROSS APPLY
					(
						--SELECT (ISNULL(URPSubtotals.TotalHoursURP, 0) + ISNULL(URPSubtotals.TotalHoursNonURP, 0)) AS TotalHoursWithoutBIM
						SELECT
							(
								CASE c.ContractPricingTypeID
									WHEN 1 THEN URPHours.TotalHoursURP
									WHEN 2 THEN NonURPHours.TotalHoursNonURP
									WHEN 3 THEN CompositeTOAHours.TotalAdjustedHoursCompositeTOA
									ELSE 0
								END
							) + ISNULL(DetailingHoursComponent.DetailingHours, 0) AS TotalHoursWithoutBIM
						--SELECT ISNULL(COALESCE(URPSubtotals.TotalHoursURP, URPSubtotals.TotalHoursNonURP), 0)) AS TotalHoursWithoutBIM
					) AS HoursWithoutBIM
					CROSS APPLY
					(
						SELECT (ISNULL(HoursWithoutBIM.TotalHoursWithoutBIM, 0) + ISNULL(BIMHoursComponent.BIMHours, 0)) AS TotalHoursWithBIM
					) AS HoursWithBIM
					CROSS APPLY
					(
						SELECT
							(TotalHoursWithoutBIM * dbo.GetConvertedRate(c.CurrencySymbol, @BaseCurrencySymbol, CCR.PricedTotalCCR)) AS LaborCost,
							(
								CASE
									WHEN MODEL.Location LIKE '%Labor Only' THEN 0
									ELSE
										ISNULL(MODEL.Quantity * dbo.GetConvertedRate(SOR.PricedUnit, Model.Unit, dbo.GetConvertedRate(c.CurrencySymbol, @BaseCurrencySymbol, SOR.PricedMaterial)) * (ISNULL(TOALocation.MaterialAdjust, 1)), 0)
								END
							) AS MaterialCost
					) AS CostComponents
					CROSS APPLY
					(
						SELECT
							(CostComponents.LaborCost + CostComponents.MaterialCost) AS LaborAndMaterial,
							CASE
								WHEN c.IndirectCalculationMethodID = 2 THEN
									-- Calculated off Labor only
									(CostComponents.LaborCost * (ISNULL(c.IndirectPCT, 0)/100))
								WHEN c.IndirectCalculationMethodID = 1 THEN
									-- Calculated off Labor and Material
									((CostComponents.LaborCost + CostComponents.MaterialCost) * (ISNULL(c.IndirectPCT, 0)/100))
								ELSE 0
							END AS IndirectCost,
							(CostComponents.LaborCost * (ISNULL(c.BIMPCT, 0)/100)) AS BIMCost,
							(CostComponents.LaborCost * (ISNULL(c.AnalyticalTesting, 0)/100)) AS AnalyticalTestingCost
					) AS ExpandedCostComponents
					CROSS APPLY
					(
						SELECT
							(ExpandedCostComponents.LaborAndMaterial + ExpandedCostComponents.IndirectCost + ExpandedCostComponents.BIMCost + ExpandedCostComponents.AnalyticalTestingCost) AS TotalCost
					) AS TotalCostCalc
					CROSS APPLY
					(
						SELECT
							(TotalCostCalc.TotalCost * (ISNULL(c.TotalCostDiscountPCT, 0)/100)) AS TotalCostDiscount
					) AS TotalCostDiscountCalc
					CROSS APPLY
					(
						SELECT
							(TotalCostCalc.TotalCost - TotalCostDiscountCalc.TotalCostDiscount) AS DiscountedTotalCost
					) AS DiscountedTotalCostCalc
				--WHERE
				--	--SOR.IsNullVoid <> 1
				--	SOR.Hide <> 1

			END


		---------- CHECKPOINT ----------
		EXEC RecordEvent @ModelRunID, 'Master Calculation Done'
		---------- CHECKPOINT ----------

	--SELECT * FROM #SingleCEIDOutputData WHERE SiteAbbreviation = 'OR'
	--SELECT * FROM #SingleCEIDOutputData WHERE SiteAbbreviation = 'IR'

	--SELECT DISTINCT * FROM #SingleCEIDOutputData WHERE SiteAbbreviation = 'OR'
	--SELECT DISTINCT * FROM #SingleCEIDOutputData WHERE SiteAbbreviation = 'IR'

	IF @IncludeMultipleCEIDOutput = 1
		BEGIN
			---------------------------------------------
			---------- MULTIPLE CEID TEMP OUTPUT --------
			---------------------------------------------
			SELECT
				BidID
				,Contractor
				,SingleCEIDOutputData.Trade
				,SingleCEIDOutputData.TradeID
				,Shortname
				,SiteAbbreviation
				,OfficialRevisionNumber
				,FriendlyRevName
				,ShortRevName
				,IsMarket
				,IsLastPricePaid
				,IsTarget
				,IsIPD
				,IndirectPCT
				,ContractorTypeVersion
				,RevImportTimestamp
				,SingleCEIDOutputData.CEID
				,FunctionalArea
				,ScopeDemarcation
				,(CEIDCount * ISNULL(CEIDMultiplier.Quantity, 1)) AS CEIDCount
				,CostCode
				,ModelItemCode
				,ItemCode
				,ModelSize
				,Size
				,Classification
				,ModelUnit
				,Unit
				,ModelSpec AS Spec--Spec
				,ModelSpecification
				--,Service -- RICK
				,UnconvertedBaseLaborInSOR
				,CAST(BaseLaborinSOR as decimal(19,4)) AS BaseLaborinSOR
				,UnconvertedBaseMaterialRate
				,CAST(BaseMaterialRate as decimal(19,4)) AS BaseMaterialRate
				,CAST((BOQQty * CEIDMultiplier.Quantity) as decimal(19,4)) AS BOQQty
				,CAST((StandardHours * CEIDMultiplier.Quantity) as decimal(19,4)) AS StandardHours
				,CAST((BuildingTOAHours * CEIDMultiplier.Quantity) as decimal(19,4)) AS BuildingTOAHours
				,CAST((LocationTOAHours * CEIDMultiplier.Quantity) as decimal(19,4)) AS LocationTOAHours
				,CAST((FunctionalAreaTOAHours * CEIDMultiplier.Quantity) as decimal(19,4)) AS FunctionalAreaTOAHours
				,CAST((ScopeDemarcationTOAHours * CEIDMultiplier.Quantity) as decimal(19,4)) AS ScopeDemarcationTOAHours
				,CAST((LaborCost * CEIDMultiplier.Quantity) as decimal(19,4)) AS LaborCost
				,CAST((MaterialCost * CEIDMultiplier.Quantity) as decimal(19,4)) AS MaterialCost
				,CAST((LaborAndMaterial * CEIDMultiplier.Quantity) as decimal(19,4)) AS LaborAndMaterial
				,CAST((IndirectCost * CEIDMultiplier.Quantity) as decimal(19,4)) AS IndirectCost
				,CAST((BIMCost * CEIDMultiplier.Quantity) as decimal(19,4)) AS BIMCost
				,CAST((AnalyticalTestingCost * CEIDMultiplier.Quantity) as decimal(19,4)) AS AnalyticalTestingCost
				,CAST((TotalCost * CEIDMultiplier.Quantity) as decimal(19,4)) AS TotalCost
				,CAST((TotalCostDiscount * CEIDMultiplier.Quantity) as decimal(19,4)) AS TotalCostDiscount
				,CAST((DiscountedTotalCost * CEIDMultiplier.Quantity) as decimal(19,4)) AS DiscountedTotalCost
				,Location
				--,hide
				--,IsNullVoid
				,TotalCCR
				,CAST((BIMHours * CEIDMultiplier.Quantity) as decimal(19,4)) AS BIMHours
				,CAST((StandardHoursURP * CEIDMultiplier.Quantity) as decimal(19,4)) AS StandardHoursURP
				,CAST((FAURP * CEIDMultiplier.Quantity) as decimal(19,4)) AS FAURP
				,CAST((LOPURP * CEIDMultiplier.Quantity) as decimal(19,4)) AS LOPURP
				,CAST((FixedURP * CEIDMultiplier.Quantity) as decimal(19,4)) AS FixedURP
				,CAST((TotalHoursURP * CEIDMultiplier.Quantity) as decimal(19,4)) AS TotalHoursURP
				,CAST((TotalHoursNonURP * CEIDMultiplier.Quantity) as decimal(19,4)) AS TotalHoursNonURP
				,CAST((VariableURP * CEIDMultiplier.Quantity) as decimal(19,4)) AS VariableURP
				,CAST((TotalHoursWithoutBIM * CEIDMultiplier.Quantity) as decimal(19,4)) AS TotalHoursWithoutBIM
				,CAST((TotalHoursWithBIM * CEIDMultiplier.Quantity) as decimal(19,4)) AS TotalHoursWithBIM
				,CAST((DetailingHours * CEIDMultiplier.Quantity) as decimal(19,4)) AS DetailingHours
			INTO #MultipleCEIDOutputData
			FROM
				#SingleCEIDOutputData AS SingleCEIDOutputData
				LEFT JOIN #ModelCEIDMultiplier CEIDMultiplier ON
					SingleCEIDOutputData.trade = CEIDMultiplier.Trade
					AND SingleCEIDOutputData.CEID = CEIDMultiplier.CEID
					AND
					(
						(SingleCEIDOutputData.TechnologyProcess = CEIDMultiplier.TechnologyProcess)
						OR
						(SingleCEIDOutputData.TechnologyProcess IS NULL AND CEIDMultiplier.TechnologyProcess IS NULL)
					)

		END

		---------- CHECKPOINT ----------
		EXEC RecordEvent @ModelRunID, 'Multiple CEID Temp table filled'
		---------- CHECKPOINT ----------








		------------- *************** -------------
		------------- *************** -------------
		-- SAVE CALCULATED DATA INTO TABLES TO BE USED FOR OUTPUTS
		------------- *************** -------------
		------------- *************** -------------

		------------------------------------------------
		------ PUT CALCULATION RESULTS INTO TABLE-------
		------------------------------------------------
		IF @IncludeMultipleCEIDOutput = 1
			BEGIN
				INSERT INTO ModelOutputReporting
					(
						[ModelRunID], [BidID], [Contractor], [trade], [TradeID], [Shortname], [SiteAbbreviation], [OfficialRevisionNumber], [FriendlyRevName], [ShortRevName], [IsMarket], [IsLastPricePaid], [IsTarget], [IsIPD], [IndirectPCT], [ContractorTypeVersion], [RevImportTimestamp], [CEID], [FunctionalArea], [ScopeDemarcation], [CEIDCount], [CostCode], [ModelItemCode], [ItemCode], [ModelSize], [Size], [Classification], [ModelUnit], [Unit], [Spec], [ModelSpecification], [UnconvertedBaseLaborInSOR], [BaseLaborinSOR], [UnconvertedBaseMaterialRate], [BaseMaterialRate], [BOQQty], [StandardHours], [BuildingTOAHours], [LocationTOAHours], [FunctionalAreaTOAHours], [ScopeDemarcationTOAHours], [LaborCost], [MaterialCost], [LaborAndMaterial], [IndirectCost], [BIMCost], [AnalyticalTestingCost], [TotalCost], [TotalCostDiscount], [DiscountedTotalCost], [Location], [TotalCCR], [BIMHours], [StandardHoursURP], [FAURP], [LOPURP], [FixedURP], [TotalHoursURP], [TotalHoursNonURP], [VariableURP], [TotalHoursWithoutBIM], [TotalHoursWithBIM]
					)
				SELECT
					@ModelRunID, [BidID], [Contractor], [trade], [TradeID], [Shortname], [SiteAbbreviation], [OfficialRevisionNumber], [FriendlyRevName], [ShortRevName], [IsMarket], [IsLastPricePaid], [IsTarget], [IsIPD], [IndirectPCT], [ContractorTypeVersion], [RevImportTimestamp], [CEID], [FunctionalArea], [ScopeDemarcation], [CEIDCount], [CostCode], [ModelItemCode], [ItemCode], [ModelSize], [Size], [Classification], [ModelUnit], [Unit], [Spec], [ModelSpecification], [UnconvertedBaseLaborInSOR], [BaseLaborinSOR], [UnconvertedBaseMaterialRate], [BaseMaterialRate], [BOQQty], [StandardHours], [BuildingTOAHours], [LocationTOAHours], [FunctionalAreaTOAHours], [ScopeDemarcationTOAHours], [LaborCost], [MaterialCost], [LaborAndMaterial], [IndirectCost], [BIMCost], [AnalyticalTestingCost], [TotalCost], [TotalCostDiscount], [DiscountedTotalCost], [Location], [TotalCCR], [BIMHours], [StandardHoursURP], [FAURP], [LOPURP], [FixedURP], [TotalHoursURP], [TotalHoursNonURP], [VariableURP], [TotalHoursWithoutBIM], [TotalHoursWithBIM]
				FROM #MultipleCEIDOutputData
			END
		ELSE
			BEGIN
				INSERT INTO ModelOutputReporting
					(
						[ModelRunID], [BidID], [Contractor], [trade], [TradeID], [Shortname], [SiteAbbreviation], [OfficialRevisionNumber], [FriendlyRevName], [ShortRevName], [IsMarket], [IsLastPricePaid], [IsTarget], [IsIPD], [IndirectPCT], [ContractorTypeVersion], [RevImportTimestamp], [CEID], [FunctionalArea], [ScopeDemarcation], [CEIDCount], [CostCode], [ModelItemCode], [ItemCode], [ModelSize], [Size], [Classification], [ModelUnit], [Unit], [Spec], [ModelSpecification], [UnconvertedBaseLaborInSOR], [BaseLaborinSOR], [UnconvertedBaseMaterialRate], [BaseMaterialRate], [BOQQty], [StandardHours], [BuildingTOAHours], [LocationTOAHours], [FunctionalAreaTOAHours], [ScopeDemarcationTOAHours], [LaborCost], [MaterialCost], [LaborAndMaterial], [IndirectCost], [BIMCost], [AnalyticalTestingCost], [TotalCost], [TotalCostDiscount], [DiscountedTotalCost], [Location], [TotalCCR], [BIMHours], [StandardHoursURP], [FAURP], [LOPURP], [FixedURP], [TotalHoursURP], [TotalHoursNonURP], [VariableURP], [TotalHoursWithoutBIM], [TotalHoursWithBIM]
					)
				SELECT
					@ModelRunID, [BidID], [Contractor], [trade], [TradeID], [Shortname], [SiteAbbreviation], [OfficialRevisionNumber], [FriendlyRevName], [ShortRevName], [IsMarket], [IsLastPricePaid], [IsTarget], [IsIPD], [IndirectPCT], [ContractorTypeVersion], [RevImportTimestamp], [CEID], [FunctionalArea], [ScopeDemarcation], [CEIDCount], [CostCode], [ModelItemCode], [ItemCode], [ModelSize], [Size], [Classification], [ModelUnit], [Unit], [Spec], [ModelSpecification], [UnconvertedBaseLaborInSOR], [BaseLaborinSOR], [UnconvertedBaseMaterialRate], [BaseMaterialRate], [BOQQty], [StandardHours], [BuildingTOAHours], [LocationTOAHours], [FunctionalAreaTOAHours], [ScopeDemarcationTOAHours], [LaborCost], [MaterialCost], [LaborAndMaterial], [IndirectCost], [BIMCost], [AnalyticalTestingCost], [TotalCost], [TotalCostDiscount], [DiscountedTotalCost], [Location], [TotalCCR], [BIMHours], [StandardHoursURP], [FAURP], [LOPURP], [FixedURP], [TotalHoursURP], [TotalHoursNonURP], [VariableURP], [TotalHoursWithoutBIM], [TotalHoursWithBIM]
				FROM #SingleCEIDOutputData
			END





	--============================================================
	------------------- PARAMETERS Output -----------------------
	--============================================================
	IF @IncludeSingleCEIDOutput = 1 OR @IncludeMultipleCEIDOutput = 1
		BEGIN

			-- Base parameters
			INSERT INTO ModelOutputParameters ([ModelRunID], [Parameter], [Value])
			SELECT @ModelRunID, Parameter, [Value]
			FROM
			(
				SELECT 'Model Run ID' as Parameter, CAST(@ModelRunID AS varchar(5)) as [Value]
				UNION ALL
				SELECT 'Model ID' as Parameter, CAST(@ModelID AS varchar(3)) as [Value]
				UNION ALL
				SELECT 'Model Name' as Parameter, @ModelName as [Value]
				UNION ALL
				SELECT 'CCR' as Parameter, @CCRName as [Value]
				UNION ALL
				SELECT 'Building' as Parameter, @OverrideBuilding as [Value] WHERE @OverrideBuilding is not null
				UNION ALL
				SELECT 'Technology' as Parameter, @TechnologyProcess as [Value] WHERE @TechnologyProcess is not null
				UNION ALL
				SELECT 'Output Currency' as Parameter, @BaseCurrencySymbol as [Value]
				UNION ALL
				SELECT 'Variable Assumptions' AS Parameter, @VariableURPAssumptionName AS [Value] WHERE @VariableURPAssumptionName is not null
				UNION ALL
				select
					'Currency Conversion (' + OtherCurrencies.CurrencySymbol + ' to ' + @BaseCurrencySymbol + ')',
					CAST(dbo.GetConvertedRate(OtherCurrencies.CurrencySymbol, @BaseCurrencySymbol, 1) AS varchar(50))
				from
					(select DISTINCT CurrencySymbol from #Contractor where CurrencySymbol <> @BaseCurrencySymbol) OtherCurrencies
			) AS ParameterData

			IF @BidTypeID = 1
			BEGIN
				/* HOPEFLULLY NO LONGER USED/NEEDED
				-- Total Cost Discounts
				SELECT DISTINCT SiteAbbreviation, Trade, Contractor, FriendlyRevName, (ISNULL(TotalCostDiscountPCT, 0)/100)
				from #SingleCEIDOutputData
				where TotalCostDiscountPCT <> 0
				order by SiteAbbreviation, Trade, FriendlyRevName
				*/

				-- Variable URP % occurences
				INSERT INTO ModelOutputVariableURPOccurences ([ModelRunID], [FunctionalArea], [Discipline], [VariableFactor], [PctOccurrence])
				SELECT
					@ModelRunID,
					FA AS [Functional Area],
					Discipline,
					SORItemFactor AS [Variable Factor],
					PctOccurrence AS [% Occurrence]
				FROM #VariableURPOcc
				--WHERE ModelID = @ModelID
				order by FA, Discipline, SORItemFactor
			END

		END



		---------- CHECKPOINT ----------
		EXEC RecordEvent @ModelRunID, 'Starting output to multiple tables'
		---------- CHECKPOINT ----------


	--============================================================
	------------------- MULTIPLE CEID Output -----------------------
	--============================================================
	IF @IncludeMultipleCEIDOutput = 1
		BEGIN


			IF @BidTypeID = 1
			BEGIN
				--Summary - Groups bids by trade
				INSERT INTO ModelOutputSummaryMultiple ([ModelRunID], [Site], [Trade], [Contractor], [Shortname], [BOSProject], [FriendlyRevName], [BOQQty], [StandardHours], [BuildingTOAHours], [LocationTOAHours], [FunctionalAreaTOAHours], [ScopeDemarcationTOAHours], [BIM], [StandardHoursURP], [FAURP], [LOPURP], [FixedURP], [VariableURP], [TotalHoursURP], [TotalHoursNonURP], [DetailingHours], [TotalHoursWithBIM], [LaborCost], [TotalMaterialCost], [LaborAndMaterial], [IndirectCost], [BIMCost], [TotalCost], [TotalCostDiscount], [DiscountedTotalCost])
				SELECT
					@ModelRunID,
					SiteAbbreviation AS [Site]
					,Trade
					,Contractor
					,Shortname
					,'' AS [BOSProject]
					,FriendlyRevName
					,sum([BOQQty]) AS [BOQQty]
					,sum(StandardHours) AS StandardHours
					,sum(BuildingTOAHours) AS BuildingTOAHours
					,sum(LocationTOAHours) AS LocationTOAHours
					,sum(FunctionalAreaTOAHours) AS FunctionalAreaTOAHours
					,sum(ScopeDemarcationTOAHours) AS ScopeDemarcationTOAHours
					,sum(BIMHours) as BIM
					,sum(StandardHoursURP) as StandardHoursURP
					,sum(FAURP) as FAURP
					,sum(LOPURP) as LOPURP
					,sum(FixedURP) as FixedURP
					,sum(VariableURP) as VariableURP
					,sum(ISNULL(TotalHoursURP, 0)) AS TotalHoursURP
					,sum(ISNULL(TotalHoursNonURP, 0)) AS TotalHoursNonURP
					,sum(ISNULL(DetailingHours, 0)) as DetailingHours
					--,sum(TotalHoursWithoutBIM) AS TotalHoursWithoutBIM
					,sum(TotalHoursWithBIM) AS TotalHoursWithBIM
					,sum(LaborCost) AS LaborCost
					,sum(MaterialCost) AS TotalMaterialCost
					,sum(LaborAndMaterial) AS LaborAndMaterial
					,sum(IndirectCost) AS IndirectCost
					,sum(BIMCost) AS BIMCost
					,sum(TotalCost) AS TotalCost
					,sum(TotalCostDiscount) AS TotalCostDiscount
					,sum(DiscountedTotalCost) AS DiscountedTotalCost
				FROM
					#MultipleCEIDOutputData M
				GROUP BY
					SiteAbbreviation
					,Contractor
					,Shortname
					,FriendlyRevName
					,trade
				ORDER BY
					trade,
					SiteAbbreviation,
					Contractor,
					FriendlyRevName
				-- End Summary




				-- CEID
				INSERT INTO ModelOutputByCEIDMultiple ([ModelRunID], [Site], [Trade], [Contractor], [Shortname], [BOSProject], [FriendlyRevName], [CEID], [CEIDCount], [FunctionalArea], [BOQQty], [StandardHours], [BuildingTOAHours], [LocationTOAHours], [FunctionalAreaTOAHours], [ScopeDemarcationTOAHours], [BIM], [StandardHoursURP], [FAURP], [LOPURP], [FixedURP], [VariableURP], [TotalHoursURP], [TotalHoursNonURP], [DetailingHours], [TotalHoursWithBIM], [LaborCost], [TotalMaterialCost], [LaborAndMaterial], [IndirectCost], [BIMCost], [TotalCost], [TotalCostDiscount], [DiscountedTotalCost])
				SELECT
					@ModelRunID,
					SiteAbbreviation AS [Site]
					,Trade
					,Contractor
					,Shortname
					,'' AS [BOSProject]
					,FriendlyRevName
					,M.CEID
					,CEIDCount
					,FunctionalArea
					,sum([BOQQty]) AS [BOQQty]
					,sum(StandardHours) AS StandardHours
					,sum(BuildingTOAHours) AS BuildingTOAHours
					,sum(LocationTOAHours) AS LocationTOAHours
					,sum(FunctionalAreaTOAHours) AS FunctionalAreaTOAHours
					,sum(ScopeDemarcationTOAHours) AS ScopeDemarcationTOAHours
					,sum(BIMHours) as BIM
					,sum(StandardHoursURP) as StandardHoursURP
					,sum(FAURP) as FAURP
					,sum(LOPURP) as LOPURP
					,sum(FixedURP) as FixedURP
					,sum(VariableURP) as VariableURP
					,sum(TotalHoursURP) as TotalHoursURP
					,sum(TotalHoursNonURP) as TotalHoursNonURP
					,sum(ISNULL(DetailingHours, 0)) as DetailingHours
					--,sum(TotalHoursWithoutBIM) AS TotalHoursWithoutBIM
					,sum(TotalHoursWithBIM) AS TotalHoursWithBIM
					,sum(LaborCost) AS LaborCost
					,sum(MaterialCost) AS TotalMaterialCost
					,sum(LaborAndMaterial) AS LaborAndMaterial
					,sum(IndirectCost) AS IndirectCost
					,sum(BIMCost) AS BIMCost
					,sum(TotalCost) AS TotalCost
					,sum(TotalCostDiscount) AS TotalCostDiscount
					,sum(DiscountedTotalCost) AS DiscountedTotalCost
				FROM
					#MultipleCEIDOutputData M
				GROUP BY
					SiteAbbreviation
					,Contractor
					,Shortname
					,FriendlyRevName
					,trade
					,M.CEID
					,CEIDCount
					,FunctionalArea
				ORDER BY
					trade,
					SiteAbbreviation,
					Contractor,
					FriendlyRevName,
					M.CEID
				-- end CEID




				-- Item Code
				INSERT INTO ModelOutputByItemCodeMultiple ([ModelRunID], [Site], [Trade], [Contractor], [Shortname], [BOSProject], [FriendlyRevName], [ModelItemCode], [ItemCode], [ScopeDemarcation], [Spec], [classification], [size], [ModelUnit], [unit], [BOQQty], [BaseLaborinSOR], [BaseMaterialInSOR], [StandardHours], [BuildingTOAHours], [LocationTOAHours], [FunctionalAreaTOAHours], [ScopeDemarcationTOAHours], [BIM], [StandardHoursURP], [FAURP], [LOPURP], [FixedURP], [VariableURP], [TotalHoursURP], [TotalHoursNonURP], [DetailingHours], [TotalHoursWithBIM], [LaborCost], [TotalMaterialCost], [LaborAndMaterial], [IndirectCost], [BIMCost], [TotalCost], [TotalCostDiscount], [DiscountedTotalCost])
				SELECT
					@ModelRunID,
					SiteAbbreviation AS [Site]
					,Trade
					,Contractor
					,Shortname
					,'' AS [BOSProject]
					,FriendlyRevName
					,ModelItemCode
					,ItemCode
					,ScopeDemarcation
					--,Service -- RICK
					,Spec
					,classification
					,size
					,ModelUnit
					,unit
					,sum([BOQQty]) AS [BOQQty]
					,BaseLaborinSOR
					,(@BaseCurrencySymbol + (CAST(CAST(BaseMaterialRate AS decimal(19,4)) AS varchar(20)))) AS BaseMaterialInSOR
					,sum(StandardHours) AS StandardHours
					,sum(BuildingTOAHours) AS BuildingTOAHours
					,sum(LocationTOAHours) AS LocationTOAHours
					,sum(FunctionalAreaTOAHours) AS FunctionalAreaTOAHours
					,sum(ScopeDemarcationTOAHours) AS ScopeDemarcationTOAHours
					,sum(BIMHours) as BIM
					,sum(StandardHoursURP) as StandardHoursURP
					,sum(FAURP) as FAURP
					,sum(LOPURP) as LOPURP
					,sum(FixedURP) as FixedURP
					,sum(VariableURP) as VariableURP
					,sum(TotalHoursURP) as TotalHoursURP
					,sum(TotalHoursNonURP) as TotalHoursNonURP
					,sum(ISNULL(DetailingHours, 0)) as DetailingHours
					--,sum(TotalHoursWithoutBIM) AS TotalHoursWithoutBIM
					,sum(TotalHoursWithBIM) AS TotalHoursWithBIM
					,sum(LaborCost) AS LaborCost
					,sum(MaterialCost) AS TotalMaterialCost
					,sum(LaborAndMaterial) AS LaborAndMaterial
					,sum(IndirectCost) AS IndirectCost
					,sum(BIMCost) AS BIMCost
					,sum(TotalCost) AS TotalCost
					,sum(TotalCostDiscount) AS TotalCostDiscount
					,sum(DiscountedTotalCost) AS DiscountedTotalCost
				FROM
					#MultipleCEIDOutputData
				GROUP BY
					SiteAbbreviation
					,Contractor
					,Shortname
					,FriendlyRevName
					,trade
					,ModelItemCode
					,ItemCode
					,ScopeDemarcation
					--,Service -- RICK
					,Spec
					,classification
					,size
					,ModelUnit
					,unit
					,BaseLaborinSOR
					,BaseMaterialRate
				ORDER BY
					trade,
					SiteAbbreviation,
					Contractor,
					FriendlyRevName,
					ItemCode
				-- end Item Code



			END

			/*
			NOT SURE WHY THIS IS HERE.  PUT BACK IF NEEDED
			IF @BidTypeID = 2
			BEGIN
				SELECT 1
			END
			*/
	END


		---------- CHECKPOINT ----------
		EXEC RecordEvent @ModelRunID, 'Starting output to single tables'
		---------- CHECKPOINT ----------


	--============================================================
	------------------- SINGLE CEID Output -----------------------
	--============================================================
	IF @IncludeSingleCEIDOutput = 1
		BEGIN

			IF @BidTypeID = 1
			BEGIN
				--Summary - Groups bids by trade
				INSERT INTO ModelOutputSummarySingle ([ModelRunID], [Site], [Trade], [Contractor], [Shortname], [BOSProject], [FriendlyRevName], [BOQQty], [StandardHours], [BuildingTOAHours], [LocationTOAHours], [FunctionalAreaTOAHours], [ScopeDemarcationTOAHours], [BIM], [StandardHoursURP], [FAURP], [LOPURP], [FixedURP], [VariableURP], [TotalHoursURP], [TotalHoursNonURP], [DetailingHours], [TotalHoursWithBIM], [LaborCost], [TotalMaterialCost], [LaborAndMaterial], [IndirectCost], [BIMCost], [TotalCost], [TotalCostDiscount], [DiscountedTotalCost])
				SELECT
					@ModelRunID,
					SiteAbbreviation AS [Site]
					,Trade
					,Contractor
					,Shortname
					,'' AS [BOSProject]
					,FriendlyRevName
					,sum([BOQQty]) AS [BOQQty]
					,sum(StandardHours) AS StandardHours
					,sum(BuildingTOAHours) AS BuildingTOAHours
					,sum(LocationTOAHours) AS LocationTOAHours
					,sum(FunctionalAreaTOAHours) AS FunctionalAreaTOAHours
					,sum(ScopeDemarcationTOAHours) AS ScopeDemarcationTOAHours
					,sum(BIMHours) as BIM
					,sum(StandardHoursURP) as StandardHoursURP
					,sum(FAURP) as FAURP
					,sum(LOPURP) as LOPURP
					,sum(FixedURP) as FixedURP
					,sum(VariableURP) as VariableURP
					,sum(TotalHoursURP) as TotalHoursURP
					,sum(TotalHoursNonURP) as TotalHoursNonURP
					,sum(ISNULL(DetailingHours, 0)) as DetailingHours
					--,sum(TotalHoursWithoutBIM) AS TotalHoursWithoutBIM
					,sum(TotalHoursWithBIM) AS TotalHoursWithBIM
					,sum(LaborCost) AS LaborCost
					,sum(MaterialCost) AS TotalMaterialCost
					,sum(LaborAndMaterial) AS LaborAndMaterial
					,sum(IndirectCost) AS IndirectCost
					,sum(BIMCost) AS BIMCost
					,sum(TotalCost) AS TotalCost
					,sum(TotalCostDiscount) AS TotalCostDiscount
					,sum(DiscountedTotalCost) AS DiscountedTotalCost
				FROM
					#SingleCEIDOutputData S
				GROUP BY
					SiteAbbreviation
					,Contractor
					,Shortname
					,FriendlyRevName
					,trade
				ORDER BY
					trade,
					SiteAbbreviation,
					Contractor,
					FriendlyRevName
				-- End Summary



				-- CEID
				INSERT INTO ModelOutputByCEIDSingle ([ModelRunID], [Site], [Trade], [Contractor], [Shortname], [BOSProject], [FriendlyRevName], [CEID], [CEIDCount], [FunctionalArea], [BOQQty], [StandardHours], [BuildingTOAHours], [LocationTOAHours], [FunctionalAreaTOAHours], [ScopeDemarcationTOAHours], [BIM], [StandardHoursURP], [FAURP], [LOPURP], [FixedURP], [VariableURP], [TotalHoursURP], [TotalHoursNonURP], [DetailingHours], [TotalHoursWithBIM], [LaborCost], [TotalMaterialCost], [LaborAndMaterial], [IndirectCost], [BIMCost], [TotalCost], [TotalCostDiscount], [DiscountedTotalCost])
				SELECT
					@ModelRunID,
					SiteAbbreviation AS [Site]
					,Trade
					,Contractor
					,Shortname
					,'' AS [BOSProject]
					,FriendlyRevName
					,S.CEID
					,CEIDCount
					,FunctionalArea
					,sum([BOQQty]) AS [BOQQty]
					,sum(StandardHours) AS StandardHours
					,sum(BuildingTOAHours) AS BuildingTOAHours
					,sum(LocationTOAHours) AS LocationTOAHours
					,sum(FunctionalAreaTOAHours) AS FunctionalAreaTOAHours
					,sum(ScopeDemarcationTOAHours) AS ScopeDemarcationTOAHours
					,sum(BIMHours) as BIM
					,sum(StandardHoursURP) as StandardHoursURP
					,sum(FAURP) as FAURP
					,sum(LOPURP) as LOPURP
					,sum(FixedURP) as FixedURP
					,sum(VariableURP) as VariableURP
					,sum(TotalHoursURP) as TotalHoursURP
					,sum(TotalHoursNonURP) as TotalHoursNonURP
					,sum(ISNULL(DetailingHours, 0)) as DetailingHours
					--,sum(TotalHoursWithoutBIM) AS TotalHoursWithoutBIM
					,sum(TotalHoursWithBIM) AS TotalHoursWithBIM
					,sum(LaborCost) AS LaborCost
					,sum(MaterialCost) AS TotalMaterialCost
					,sum(LaborAndMaterial) AS LaborAndMaterial
					,sum(IndirectCost) AS IndirectCost
					,sum(BIMCost) AS BIMCost
					,sum(TotalCost) AS TotalCost
					,sum(TotalCostDiscount) AS TotalCostDiscount
					,sum(DiscountedTotalCost) AS DiscountedTotalCost
				FROM
					#SingleCEIDOutputData S
				GROUP BY
					SiteAbbreviation
					,Contractor
					,Shortname
					,FriendlyRevName
					,trade
					,S.CEID
					,CEIDCount
					,FunctionalArea
				ORDER BY
					trade,
					SiteAbbreviation,
					Contractor,
					FriendlyRevName,
					S.CEID
				-- end CEID




				-- Item Code
				INSERT INTO ModelOutputByItemCodeSingle ([ModelRunID], [Site], [Trade], [Contractor], [Shortname], [BOSProject], [FriendlyRevName], [ModelItemCode], [ItemCode], [ScopeDemarcation], [Spec], [classification], [size], [ModelUnit], [unit], [BOQQty], [BaseLaborinSOR], [BaseMaterialinSOR], [StandardHours], [BuildingTOAHours], [LocationTOAHours], [FunctionalAreaTOAHours], [ScopeDemarcationTOAHours], [BIM], [StandardHoursURP], [FAURP], [LOPURP], [FixedURP], [VariableURP], [TotalHoursURP], [TotalHoursNonURP], [DetailingHours], [TotalHoursWithBIM], [LaborCost], [TotalMaterialCost], [LaborAndMaterial], [IndirectCost], [BIMCost], [TotalCost], [TotalCostDiscount], [DiscountedTotalCost])
				SELECT
					@ModelRunID,
					SiteAbbreviation AS [Site]
					,Trade
					,Contractor
					,Shortname
					,'' AS [BOSProject]
					,FriendlyRevName
					,ModelItemCode
					,ItemCode
					,ScopeDemarcation
					--,Service -- RICK
					,Spec
					,classification
					,size
					,ModelUnit
					,unit
					,sum([BOQQty]) AS [BOQQty]
					,BaseLaborinSOR
					,(@BaseCurrencySymbol + (CAST(CAST(BaseMaterialRate AS decimal(19,4)) AS varchar(20)))) AS BaseMaterialinSOR
					,sum(StandardHours) AS StandardHours
					,sum(BuildingTOAHours) AS BuildingTOAHours
					,sum(LocationTOAHours) AS LocationTOAHours
					,sum(FunctionalAreaTOAHours) AS FunctionalAreaTOAHours
					,sum(ScopeDemarcationTOAHours) AS ScopeDemarcationTOAHours
					,sum(BIMHours) as BIM
					,sum(StandardHoursURP) as StandardHoursURP
					,sum(FAURP) as FAURP
					,sum(LOPURP) as LOPURP
					,sum(FixedURP) as FixedURP
					,sum(VariableURP) as VariableURP
					,sum(TotalHoursURP) as TotalHoursURP
					,sum(TotalHoursNonURP) as TotalHoursNonURP
					,sum(ISNULL(DetailingHours, 0)) as DetailingHours
					--,sum(TotalHoursWithoutBIM) AS TotalHoursWithoutBIM
					,sum(TotalHoursWithBIM) AS TotalHoursWithBIM
					,sum(LaborCost) AS LaborCost
					,sum(MaterialCost) AS TotalMaterialCost
					,sum(LaborAndMaterial) AS LaborAndMaterial
					,sum(IndirectCost) AS IndirectCost
					,sum(BIMCost) AS BIMCost
					,sum(TotalCost) AS TotalCost
					,sum(TotalCostDiscount) AS TotalCostDiscount
					,sum(DiscountedTotalCost) AS DiscountedTotalCost
				FROM
					#SingleCEIDOutputData
				GROUP BY
					SiteAbbreviation
					,Contractor
					,Shortname
					,FriendlyRevName
					,trade
					,ModelItemCode
					,ItemCode
					,ScopeDemarcation
					--,Service -- RICK
					,Spec
					,classification
					,size
					,ModelUnit
					,unit
					,BaseLaborinSOR
					,BaseMaterialRate
				ORDER BY
					trade,
					SiteAbbreviation,
					Contractor,
					FriendlyRevName,
					ItemCode
				-- end Item Code


			END

			IF @BidTypeID = 2
			BEGIN
				--Summary - Groups bids by trade
				INSERT INTO ModelOutputSummary_BB ([ModelRunID], [Site], [Trade], [Contractor], [Shortname], [FriendlyRevName], [BOQQty], [StandardHours], [AdjustedHours], [TotalCCR], [LaborCost], [TotalMaterialCost], [LaborAndMaterial], [IndirectsPct], [IndirectCost], [TotalCost])
				SELECT
					@ModelRunID,
					SiteAbbreviation AS [Site]
					,Trade
					,Contractor
					,Shortname
					,FriendlyRevName
					,sum([BOQQty]) AS [BOQQty]
					,sum(StandardHours) AS BaseHours
					,sum(TotalHoursWithoutBIM) AS AdjustedHours
					,TotalCCR
					,sum(LaborCost) AS LaborCost
					,sum(MaterialCost) AS TotalMaterialCost
					,sum(LaborAndMaterial) AS LaborAndMaterial
					,IndirectPCT
					,sum(IndirectCost) AS IndirectCost
					,sum(TotalCost) AS TotalCost
				FROM
					#SingleCEIDOutputData
				GROUP BY
					SiteAbbreviation
					,Contractor
					,Shortname
					,FriendlyRevName
					,trade
					,TotalCCR
					,IndirectPCT
				ORDER BY
					trade,
					SiteAbbreviation,
					Contractor,
					FriendlyRevName
				-- End Summary



				-- Item Code
				INSERT INTO ModelOutputByItemCode_BB ([ModelRunID], [Site], [Trade], [Contractor], [Shortname], [FriendlyRevName], [ModelItemCode], [ItemCode], [ScopeDemarcation], [Spec], [classification], [size], [ModelUnit], [unit], [BOQQty], [BaseLaborinSOR], [BaseMaterialInSOR], [StandardHours], [AdjustedHours], [LaborCost], [TotalMaterialCost], [LaborAndMaterial], [IndirectCost], [TotalCost])
				SELECT
					@ModelRunID,
					SiteAbbreviation AS [Site]
					,Trade
					,Contractor
					,Shortname
					,FriendlyRevName
					,ModelItemCode
					,ItemCode
					,ScopeDemarcation
					,Spec
					,classification
					,size
					,ModelUnit
					,unit
					,sum([BOQQty]) AS [BOQQty]
					,BaseLaborinSOR
					,(@BaseCurrencySymbol + (CAST(CAST(BaseMaterialRate AS decimal(19,4)) AS varchar(20))))
					,sum(StandardHours) AS StandardHours
					,sum(TotalHoursWithoutBIM) AS AdjustedHours
					,sum(LaborCost) AS LaborCost
					,sum(MaterialCost) AS TotalMaterialCost
					,sum(LaborAndMaterial) AS LaborAndMaterial
					,sum(IndirectCost) AS IndirectCost
					,sum(TotalCost) AS TotalCost
				FROM
					#SingleCEIDOutputData
				GROUP BY
					SiteAbbreviation
					,Contractor
					,Shortname
					,FriendlyRevName
					,trade
					,ModelItemCode
					,ItemCode
					,ScopeDemarcation
					--,Service -- RICK
					,Spec
					,classification
					,size
					,ModelUnit
					,unit
					,BaseLaborinSOR
					,BaseMaterialRate
				ORDER BY
					trade,
					SiteAbbreviation,
					Contractor,
					FriendlyRevName,
					ItemCode
				-- end Item Code
			END



		END


		---------- CHECKPOINT ----------
		EXEC RecordEvent @ModelRunID, 'All output tables filled'
		---------- CHECKPOINT ----------




		IF @OutputTypeID IN (1, 3)
		-- These are Output Types where we SELECT to screen
		BEGIN
			---------- CHECKPOINT ----------
			EXEC RecordEvent @ModelRunID, 'Executing Excluded Items'
			---------- CHECKPOINT ----------
			exec  BidModel.[dbo].[HiddenItemCodeMaster] @ModelRunID, @Technologyprocess, @ContractorBidList, @ItemCodeMappingSiteID


			---------- CHECKPOINT ----------
			EXEC RecordEvent @ModelRunID, 'Aggregating for reporting'
			---------- CHECKPOINT ----------
			exec BidModel.[dbo].[ModelOutputDataAggregator_V3] @ModelRunID


		END



	-- Update the Run completion time
	UPDATE ModelRun
	SET CompletionTimestamp = getdate()
	WHERE ID = @ModelRunID

	
	
	---------- CHECKPOINT ----------
	EXEC RecordEvent @ModelRunID, 'Cleaning up temp table'
	---------- CHECKPOINT ----------


	-- Clean up our temp tables
	IF OBJECT_ID('tempdb..#Contractor') IS NOT NULL DROP TABLE #Contractor
	IF OBJECT_ID('tempdb..#BidIDs') IS NOT NULL DROP TABLE #BidIDs
	IF OBJECT_ID('tempdb..#SOR') IS NOT NULL DROP TABLE #SOR
	IF OBJECT_ID('tempdb..#CCR') IS NOT NULL DROP TABLE #CCR
	IF OBJECT_ID('tempdb..#TOA') IS NOT NULL DROP TABLE #TOA
	IF OBJECT_ID('tempdb..#Model') IS NOT NULL DROP TABLE #Model
	IF OBJECT_ID('tempdb..#ModelWithHidden') IS NOT NULL DROP TABLE #ModelWithHidden
	IF OBJECT_ID('tempdb..#FullModelMapping') IS NOT NULL DROP TABLE #FullModelMapping
	IF OBJECT_ID('tempdb..#FullModelMappingMatch') IS NOT NULL DROP TABLE #FullModelMappingMatch
	IF OBJECT_ID('tempdb..#FullModelMappingNoMatch') IS NOT NULL DROP TABLE #FullModelMappingNoMatch
	IF OBJECT_ID('tempdb..#ModelCEIDMultiplier') IS NOT NULL DROP TABLE #ModelCEIDMultiplier
	IF OBJECT_ID('tempdb..#SingleCEIDOutputData') IS NOT NULL DROP TABLE #SingleCEIDOutputData
	IF OBJECT_ID('tempdb..#MultipleCEIDOutputData') IS NOT NULL DROP TABLE #MultipleCEIDOutputData
	IF OBJECT_ID('tempdb..#VariableURP') IS NOT NULL DROP TABLE #VariableURP
	IF OBJECT_ID('tempdb..#VariableURPOcc') IS NOT NULL DROP TABLE #VariableURPOcc
	IF OBJECT_ID('tempdb..#CCRMaps') IS NOT NULL DROP TABLE #CCRMaps
	IF OBJECT_ID('tempdb..#BuildingMaps') IS NOT NULL DROP TABLE #BuildingMaps
	IF OBJECT_ID('tempdb..#FAMaps') IS NOT NULL DROP TABLE #FAMaps
	IF OBJECT_ID('tempdb..#URPFAMaps') IS NOT NULL DROP TABLE #URPFAMaps
	IF OBJECT_ID('tempdb..#LevelMaps') IS NOT NULL DROP TABLE #LevelMaps
	IF OBJECT_ID('tempdb..#ScopeDemarcationMaps') IS NOT NULL DROP TABLE #ScopeDemarcationMaps
	IF OBJECT_ID('tempdb..#BuildingLOPMaps') IS NOT NULL DROP TABLE #BuildingLOPMaps
	IF OBJECT_ID('tempdb..#BidIDs') IS NOT NULL DROP TABLE #BidIDs
	IF OBJECT_ID('tempdb..#Techs') IS NOT NULL DROP TABLE #Techs
	IF OBJECT_ID('tempdb..#NoScopeItemCodes') IS NOT NULL DROP TABLE #NoScopeItemCodes
	IF OBJECT_ID('tempdb..#ItemCodeSites') IS NOT NULL DROP TABLE #ItemCodeSites
	IF OBJECT_ID('tempdb..#ItemCodeTradeIDs') IS NOT NULL DROP TABLE #ItemCodeTradeIDs
	IF OBJECT_ID('tempdb..#MappedSOR') IS NOT NULL DROP TABLE #MappedSOR
	IF OBJECT_ID('tempdb..#MappedCCR') IS NOT NULL DROP TABLE #MappedCCR



	-- RETURN our Model Run ID back in the output parameter
	RETURN;

