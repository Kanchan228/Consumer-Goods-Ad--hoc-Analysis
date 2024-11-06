-- 1.  Provide the list of markets in which customer "Atliq Exclusive" operates its business in the APAC region.
SELECT
    market
FROM dim_customer 
WHERE customer = 'Atliq Exclusive' AND 
region = 'APAC';

------------------------------------------------------------------------------------------------------
-- 2. What is the percentage of unique product increase in 2021 vs. 2020?
SELECT 
     a.unique_product_2020,
     b.unique_product_2021, 
    ROUND((b.unique_product_2021-a.unique_product_2020) * 100/a.unique_product_2020,2) AS pct_change
FROM(
   SELECT 
   COUNT(DISTINCT product_code) AS unique_product_2020 
FROM fact_sales_monthly 
WHERE fiscal_year = 2020) a
JOIN
   (SELECT COUNT(DISTINCT product_code) AS unique_product_2021 
FROM fact_sales_monthly 
WHERE fiscal_year = 2021) b;

--------------------------------------------------------------------------------------------------------
-- 3.Provide a report with all the unique product counts for each segment and sort them in descending order of product counts.

SELECT
   segment,
   COUNT(DISTINCT product_code) AS product_count
FROM dim_product
GROUP BY  segment
ORDER BY  product_count DESC;

-- Extra analysis
# Unsold Product (that are not in fact sale monthly)
SELECT segment, COUNT( distinct product_code) as product_count
FROM dim_product
WHERE product_code NOT IN (SELECT product_code FROM fact_sales_monthly)
group by segment order by product_count desc;

# Gross sales of segment wise sales
SELECT
   p.segment, count( distinct p.product_code) product_count,
   round(sum(s.sold_quantity * g.gross_price)/1000000,2) as gross_sales_mln
FROM dim_product p  
left join fact_sales_monthly s
 on p.product_code = s.product_code
 left join fact_gross_price g on s.product_code = g.product_code 
GROUP BY  segment
ORDER BY  gross_sales_mln DESC;

-------------------------------------------------------------------------------------------------------------------
-- 4. Follow-up: Which segment had the most increase in unique products in 2021 vs 2020?

SELECT 
      a.segment, a.no_of_product_2020,
      b.no_product_2021,
	  no_product_2021-no_of_product_2020 AS difference
 FROM
(SELECT p.segment,
 COUNT(DISTINCT s.product_code) AS no_of_product_2020 
 FROM fact_sales_monthly s
 JOIN dim_product p 
      ON s.product_code = p.product_code
 WHERE fiscal_year = 2020 
 GROUP BY  p.segment) a
 JOIN
(SELECT 
p.segment, COUNT(DISTINCT s.product_code) AS no_product_2021 
FROM fact_sales_monthly s 
     JOIN dim_product p ON s.product_code = p.product_code 
WHERE fiscal_year = 2021 
GROUP BY  p.segment) b
     ON a.segment = b.segment
ORDER BY  difference DESC ;
------------------------------------------------------------
-- 5. Get the products that have the highest and lowest manufacturing costs
SELECT m.product_code, p.product,
	   manufacturing_cost
FROM fact_manufacturing_cost m 
JOIN dim_product p 
	 ON m.product_code = p.product_code
WHERE manufacturing_cost IN (
SELECT MIN(manufacturing_cost) FROM fact_manufacturing_cost
UNION
 SELECT MAX(manufacturing_cost)  FROM fact_manufacturing_cost);
----

with max_min_manufacturing_cost as (
select m.product_code,
 p.product,
manufacturing_cost,
rank() over(order by manufacturing_cost desc) as highest_manufacturing_cost,
rank() over(order by manufacturing_cost ) as lowest_manufacturing_cost
from fact_manufacturing_cost m 
join dim_product p 
on p.product_code = m.product_code)
select product_code, product,
round(manufacturing_cost,2) as manufacturing_cost
from max_min_manufacturing_cost
 where highest_manufacturing_cost=1 or
lowest_manufacturing_cost = 1;
-----------------------------------------------------------------------------------
/* 6. Generate a report which contains the top 5 customers who received an average high 
 pre_invoice_discount_pct for the fiscal year 2021 and in the Indian market. */
SELECT 
     c.customer_code,
     c.customer, 
     CONCAT(ROUND(AVG(pre_invoice_discount_pct)* 100,2), '%') AS avg_discount_pct
FROM dim_customer c 
JOIN fact_pre_invoice_deductions p 
     ON c.customer_code = p.customer_code
WHERE fiscal_year = 2021 AND 
      market = 'india'
GROUP BY  c.customer_code, c.customer 
ORDER BY AVG(pre_invoice_discount_pct) DESC
LIMIT 5;

-------------------------------------------------------------------------------------

-- 7.Get the complete report of the Gross sales amount for the customer “Atliq Exclusive” for each month.
SELECT 
     MONTHNAME(DATE) AS month, 
     s.fiscal_year,
     ROUND(SUM(gross_price * sold_quantity)/1000000,2) AS gross_sales_mln
FROM fact_sales_monthly s 
JOIN fact_gross_price g USING(product_code)
JOIN dim_customer c USING(customer_code)
WHERE customer = 'atliq exclusive'
GROUP BY month, s.fiscal_year,c.customer;

-------------------------------------------------------------------
-- 8. In which quarter of 2020, got the maximum total_sold_quantity?

WITH cte AS (
SELECT fiscal_year,
CASE WHEN MONTH(date) IN (9,10,11) THEN 'Q1'
     WHEN MONTH(date) IN(12,1,2) THEN 'Q2'
	 WHEN MONTH(date) IN (3,4,5) THEN 'Q3'
	 ELSE 'Q4'
	END AS quarters,
    sold_quantity FROM fact_sales_monthly)
SELECT quarters, 
ROUND(SUM(sold_quantity)/1000000,2) AS total_sold_quantity_mln
FROM cte
WHERE fiscal_year = 2020
GROUP BY  quarters
ORDER BY  total_sold_quantity_mln DESC;
-------------------------------------------------------------
-- 9.Which channel helped to bring more gross sales in the fiscal year 2021 and the pct of contribution?
WITH cte AS (
    SELECT 
        c.channel,
        (s.sold_quantity * g.gross_price) / 1000000 AS gross_sales
    FROM fact_sales_monthly s 
    JOIN fact_gross_price g 
        ON s.product_code = g.product_code 
    JOIN dim_customer c 
        ON s.customer_code = c.customer_code
    WHERE s.fiscal_year = 2021)
SELECT 
    channel,
    CONCAT(ROUND(SUM(gross_sales),2), 'M') AS total_gross_sales,
    CONCAT(ROUND(SUM(SUM(gross_sales)) OVER (PARTITION BY channel)*100 / SUM(SUM(gross_sales)) OVER (),2), '%')
    AS pct_contribution
FROM cte
GROUP BY channel
order by pct_contribution desc ;
---------------------------------------------------------------------------------

-- 10. Get the Top 3 products in each division that have high total_sold_quantity in the fiscal_year 2021?
WITH product_rank AS(
SELECT 
     p.division,
	 s.product_code,
     CONCAT(p.product, ' ',P.VARIANT) AS Product, p.category,
     sum(s.sold_quantity) as total_sold_qty,
     DENSE_RANK() OVER (PARTITION BY division ORDER BY sum(s.sold_quantity) DESC) AS rank_order
FROM fact_sales_monthly s 
JOIN dim_product p 
     ON s.product_code = p.product_code
WHERE fiscal_year = 2021
GROUP BY  division,s.product_code, p.category, CONCAT(p.product, ' ',P.variant))
SELECT *
FROM product_rank
WHERE rank_order <=3;



