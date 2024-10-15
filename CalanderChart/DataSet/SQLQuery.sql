DROP TABLE TempTable;

WITH DateRange
AS (
	-- This CTE generates all dates between a given range
	SELECT CAST('2024-09-01' AS DATE) AS [Appointment Date] -- Start Date
	
	UNION ALL
	
	SELECT DATEADD(DAY, 1, [Appointment Date])
	FROM DateRange
	WHERE [Appointment Date] < CAST(dateadd(day, 60, GETDATE()) AS DATE) -- End Date (current date)
	)
SELECT *
INTO TempTable
FROM (
	SELECT cal.[Appointment Date]
		,ISNULL(pvt.[Practice ID], 1090) AS [Practice ID]
		,-- Use 0 or NULL for missing Practice ID
		nullif(ISNULL([Appeal], NULL), 0) AS Appeal
		,nullif(ISNULL([Approved], NULL), 0) AS Approved
		,nullif(ISNULL([Cancelled], NULL), 0) AS Cancelled
		,nullif(ISNULL([Clinical submitted to Carrier], NULL), 0) AS [Clinical Submitted to Carrier]
		,nullif(ISNULL([Denied], NULL), 0) AS Denied
		,nullif(ISNULL([In-process], NULL), 0) AS [In-process]
		,nullif(ISNULL([Lack of Clinical], NULL), 0) AS [Lack of Clinical]
		,nullif(ISNULL([No-Auth required], NULL), 0) AS [No-Auth Required]
		,nullif(ISNULL([Peer to Peer], NULL), 0) AS [Peer to Peer]
		,nullif(ISNULL([Scheduled], NULL), 0) AS Scheduled
		,CASE 
			WHEN ISNULL([Appeal], 0) + ISNULL([Approved], 0) + ISNULL([No-Auth required], 0) + ISNULL([Denied], 0) > 0
				THEN 'color'
			ELSE ' no color'
			END coloring
	FROM DateRange cal
	LEFT JOIN (
		SELECT [Practice ID]
			,[Appointment Date]
			,ISNULL([Appeal], NULL) AS Appeal
			,ISNULL([Approved], NULL) AS Approved
			,ISNULL([Cancelled], NULL) AS Cancelled
			,ISNULL([Clinical submitted to Carrier], NULL) AS [Clinical Submitted to Carrier]
			,ISNULL([Denied], NULL) AS Denied
			,ISNULL([In-process], NULL) AS [In-process]
			,ISNULL([Lack of Clinical], NULL) AS [Lack of Clinical]
			,ISNULL([No-Auth required], NULL) AS [No-Auth Required]
			,ISNULL([Peer to Peer], NULL) AS [Peer to Peer]
			,ISNULL([Scheduled], NULL) AS Scheduled
		FROM (
			SELECT o.[Order ID]
				,o.[Practice ID]
				,o.[Appointment Date]
				,ISNULL(os.[Status Description], 'Scheduled') AS [Order Status]
			FROM tbl_order o
			LEFT JOIN tbl_order_procedure op ON o.[Order ID] = op.[Order ID]
			LEFT JOIN tbl_order_status os ON op.[CPT Status ID] = os.[Status ID]
			WHERE op.[CPT Code] IS NULL
				OR op.[CPT Code] IS NOT NULL
			) AS source_data
		PIVOT(COUNT([Order ID]) FOR [Order Status] IN (
					[Appeal]
					,[Approved]
					,[Cancelled]
					,[Clinical submitted to Carrier]
					,[Denied]
					,[In-process]
					,[Lack of Clinical]
					,[No-Auth required]
					,[Peer to Peer]
					,[Scheduled]
					)) AS pvt
		) pvt ON cal.[Appointment Date] = pvt.[Appointment Date]
	) a
