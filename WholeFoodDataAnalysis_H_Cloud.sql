USE fmban_sql_analysis;

DESC fmban_data;


/*
Prepare the data to make it compareable. Clean up all units, prices and amounts
I'll copy this section as subquery for all further calculations, as we can't create temporary tables
*/

/*
If we were allowed to create tables it looks like this, but we can only use with

CREATE TABLE fmban_sql_analysis.WholeFoods
(ID varchar(5),
 category varchar(100), 
 subcategory varchar(100), 
 product varchar(100), 
 size float, 
 units varchar(5),
 pricePro100g float,
 price float, 
 vegan varchar(1), 
 glutenfree varchar(1), 
 ketofriendly varchar(1), 
 vegetarian varchar(1), 
 organic varchar(1), 
 dairyfree varchar(1), 
 sugarconscious varchar(1), 
 paleofriendly varchar(1), 
 wholefoodsdiet varchar(1), 
 lowsodium varchar(1), 
 kosher varchar(1), 
 lowfat varchar(1), 
 engine2 varchar(1), 
 `local` varchar(1),
 liquid varchar(1)
);

INSERT INTO sys.WholeFoods (ID, category,  subcategory ,  product ,  size ,  units, pricePro100g , price ,  vegan ,  glutenfree ,  ketofriendly ,  vegetarian,  organic ,  dairyfree, sugarconscious ,  paleofriendly , wholefoodsdiet , lowsodium, kosher ,  lowfat, engine2, `local`, liquid)
*/


WITH WholeFoodsClean AS
(SELECT * , 
-- To compare the the products, normalize all values to prices by 100 grams of the cleaned data
	IF(totalsecondarysize != 0 AND price != 0, (price/totalsecondarysize)/100,NULL) as DollarPerGramm,
-- Is food healty? The following cases show us wheater something is healthy or not covering the whole database
    CASE
	WHEN n_category LIKE "%FRESH%" THEN 'healthy'
	WHEN n_category LIKE "%Snacks%" THEN 'unhealthy'
	WHEN n_category LIKE "%Desserts%" THEN 'unhealthy'
	WHEN abv > 0.5 THEN 'unhealthy'
	WHEN lowfat = 1 THEN 'healthy'
	WHEN dairyfree = 1 THEN 'healthy'
	WHEN organic = 1 THEN 'healthy'
	WHEN sugarconscious = 1 THEN 'healthy'
	WHEN lowfat = 1 THEN 'healthy'
	WHEN wholefoodsdiet = 1 AND ketofriendly = 1 AND paleofriendly = 1 THEN 'healthy'
   	WHEN subcategory LIKE "%Ice Cream%" THEN 'unhealthy'
   	WHEN n_category LIKE "%Prepared%" THEN 'unhealthy'
    ELSE 'unhealthy' END as health_status
FROM
(SELECT ID, n_category, subcategory, product, 

-- all the attributes to describe healty-ness
	vegan, glutenfree, ketofriendly, vegetarian, organic, dairyfree, sugarconscious, paleofriendly, wholefoodsdiet, lowsodium, kosher, lowfat, engine2, `local`,
-- Format the price, if it contains a . somewhere multiply it by 100 and remove decimals	
    IF(price LIKE '%.%', CAST(ROUND(price * 100,0) as double),CAST(price AS double)) as price,
    caloriesperserving, servingsize, servingsizeunits, totalsize, n_totalsizeunits, 
-- Use totalsecondarysize as general comparison in grams, add the totalsize if it is in grams
    IF(totalsecondarysize = '0' AND n_totalsizeunits LIKE 'g' AND totalsize NOT LIKE '0',totalsize, 
		IF(totalsecondarysize = 'NULL' AND n_category IN ('Beer','Wine'),quantity*servingsize*28.3495, totalsecondarysize)) as totalsecondarysize,
-- Format the secondarysizeunits. First replace grams by g
	IF(secondarysizeunits = 'grams', 'g', 
-- If totalsecondarysize is used, also add g to the unit
		IF(n_totalsizeunits = 'g' AND totalsize != '0','g',
-- Clean UP: some liquids and snacks are missing the unit, it the totalsecondarysize divided by the total size matches ca. 29, then also add g as unit
			IF((subcategory LIKE '%Juice%'
				OR subcategory LIKE '%Drink%'
				OR subcategory LIKE '%Coffee%'
				OR subcategory LIKE '%Tea%'
				OR subcategory LIKE '%Water%') 
                AND  totalsecondarysize/totalsize > 29 
                AND totalsecondarysize/totalsize < 31 ,'g',
-- all drinks are calculared in grams, so add g as unit
					IF(n_category IN ('Beer','Wine'),'g',secondarysizeunits)))) 
                as secondarysizeunits,
-- Find out, if a food is a liquid or something to eat
	IF(category LIKE '%Beer%'
		OR category LIKE '%Wine%'
		OR subcategory LIKE '%Juice%'
		OR subcategory LIKE '%Drink%'
		OR subcategory LIKE '%Coffee%'
		OR subcategory LIKE '%Tea%'
		OR subcategory LIKE '%Water%'
-- 		OR product LIKE '%Beer%' OR product LIKE '%Wine%' OR product LIKE '%Juice%' OR product LIKE '%Drink%' OR product LIKE '%Coffee%' OR product LIKE '%Tea%' OR product LIKE '%Water%'
        ,1,'0') as liquid,
-- add ALKOHOL Data 
	abv, quantity
FROM (SELECT *, 
-- One category is missing the description, manually adding Snacks here
	IF(category = 'NULL', 'Snacks, Chips, Salsas & Dips', category) as n_category, 
-- All secondary data from snacks is in grams as size * 29.5 = oz    
    IF(category = 'NULL', 'g',totalsizeunits) as n_totalsizeunits
    FROM fmban_data) as dat1
-- Some data is missing the price, remove this data
WHERE price != 0) AS dat2
WHERE secondarysizeunits = 'g'
	AND totalsecondarysize != 0)
    
-- !!!!! PASE THE QUERYS HERE !!!!!!

SELECT *
FROM WholeFoodsClean;

-- 
-- The following code snippets are used to calculate all values for the word document and excel sheet, 
-- !!!!!!!!!just paste them into the WITH Function above to try them!!!!!!!!!!!!!!!!!!
--

-- List all products by ordered by their price
SELECT n_category, product, health_status, price, totalsecondarysize, DollarPerGramm
FROM WholeFoodsClean 
ORDER BY DollarPerGramm DESC;

-- Count all groups and give average prices    
SELECT liquid, n_category, health_status, count(health_status), avg(DollarPerGramm)
FROM WholeFoodsClean 
GROUP BY liquid, n_category, health_status;

-- Do healthier foods cost less?
-- Analysis to further compare the prices of healthy and unhealthy products of categories that conatin both
SELECT healthy1.n_category, healthy1.healthy_price, un.unhealthy_price FROM (
	SELECT n_category, avg(DollarPerGramm) as healthy_price
	FROM WholeFoodsClean 
	WHERE health_status = 'healthy'
		AND liquid = 0
	GROUP BY n_category) as healthy1
JOIN (SELECT unhealthy1.n_category, unhealthy1.unhealthy_price FROM (
	SELECT n_category, avg(DollarPerGramm) as unhealthy_price
	FROM WholeFoodsClean 
	WHERE health_status = 'unhealthy'
		AND liquid = 0
	GROUP BY n_category) as unhealthy1) as un
USING (n_category);

-- Actonable Insights
-- 1. Insight Shrink
-- Calculate the Ratio productsize in relation to the totalsecondarysoze
SELECT n_category as Category, CONCAT(ROUND(avg(DollarPerGramm),2)," $/g") as AveragePricePerGram, 
CONCAT(ROUND(avg(totalsecondarysize),2)," g") as AverageSize, 
ROUND(avg(DollarPerGramm) / avg(totalsecondarysize),10) as Ratio
FROM WholeFoodsClean 
GROUP BY n_category
ORDER BY Ratio DESC;

-- 2. Marketing startegy
-- Calculate the Ratio productsize in relation to the totalsecondarysoze
SELECT n_category as Category, CONCAT(ROUND(avg(DollarPerGramm),2)," $/g") as AveragePrice, 
CONCAT(ROUND(avg(totalsecondarysize),2)," g") as AverageSize 
FROM WholeFoodsClean 
GROUP BY n_category
ORDER BY Ratio DESC;

