-- 1) Change over time Analysis - Analyze how a measure evolves over a time

SELECT YEAR(order_date) AS order_year,
MONTH(order_date) AS order_month,
SUM(CAST(sales_amount AS BIGINT)) AS total_sales,
COUNT(DISTINCT customer_key) AS total_customer,
SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date),MONTH(order_date)
ORDER BY YEAR(order_date),MONTH(order_date)

--can also use datetrunc to have the same result
SELECT DATETRUNC(month,order_date) AS order_date,
SUM(CAST(sales_amount AS BIGINT)) AS total_sales,
COUNT(DISTINCT customer_key) AS total_customer,
SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(month,order_date)
ORDER BY DATETRUNC(month,order_date)

--If we want to change format
SELECT FORMAT(order_date, 'yyyy-MMM') AS order_date,
SUM(CAST(sales_amount AS BIGINT)) AS total_sales,
COUNT(DISTINCT customer_key) AS total_customer,
SUM(quantity) as total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY FORMAT(order_date, 'yyyy-MMM') 
ORDER BY FORMAT(order_date, 'yyyy-MMM') 


--2) Cumulative analysis -- Aggregate the data progressively over time

-- Calculate the total sales per month and the running total of sales over time

SELECT order_date,
total_sales,
SUM(total_sales) OVER(PARTITION BY order_date ORDER BY order_date) AS running_total_sales,
AVG(avg_price) OVER(PARTITION BY order_date ORDER BY order_date) AS moving_avg_price

FROM
(
SELECT DATETRUNC(month,order_date) AS order_date,
SUM(CAST(sales_amount AS BIGINT)) AS total_sales,
AVG(price) AS avg_price
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(month,order_date)
)t

--3) Performance Analysis -- Comparing a current value to a target value

--Analyze the yearly performance of products by comparing their sales
--To both its avg sales performance and the previous year's sales

WITH yearly_product_sales AS (  --CTE
SELECT YEAR(f.order_date) AS order_year, 
p.product_name, 
SUM(CAST(f.sales_amount AS BIGINT)) AS current_sales
FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
ON f.product_key = p.product_key
WHERE order_date IS NOT NULL
GROUP BY YEAR(f.order_date),p.product_name
)
SELECT order_year,
product_name,
current_sales,
AVG(current_sales) OVER(PARTITION BY product_name) AS avg_sales,
current_sales - AVG(current_sales) OVER(PARTITION BY product_name) AS diff_avg,
CASE WHEN current_sales - AVG(current_sales) OVER(PARTITION BY product_name) > 0 THEN 'Above average'
	 WHEN current_sales - AVG(current_sales) OVER(PARTITION BY product_name) < 0 THEN 'Below average'
	 ELSE 'Avg'
END avg_change,
LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) AS previous_year_sales,
current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) diff_previous_year_sales,
CASE WHEN current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Sales Increased'
	 WHEN current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Sales Decreased'
	 ELSE 'No change'
END previous_change
FROM yearly_product_sales
GO

--4) Part to whole analysis -- Analyze how an individual part is performing compared to the overall

--Which category contribute the most to overall sales

WITH category_sales AS (
SELECT p.category,
SUM(CAST(f.sales_amount AS BIGINT)) total_sales FROM gold.fact_sales f
LEFT JOIN gold.dim_products p
ON p.product_key = f.product_key
GROUP BY category
)
SELECT
category,
total_sales,
SUM(total_sales) OVER() overall_sales,
CONCAT(ROUND((CAST(total_sales AS FLOAT)/ SUM(total_sales) OVER()) * 100,2),'%') AS percentage_of_total
FROM category_sales
ORDER BY total_sales DESC
GO

--5) Data Segmentation -- Group the data based on a specific range

--Segment products into cost ranges and count how many products fall into each category

WITH product_segment AS(

SELECT product_key,product_name,cost,
CASE WHEN cost < 100 THEN 'Below 100'
	 WHEN cost BETWEEN 100 AND 500 THEN '100-500'
	 WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
	 ELSE 'Above 1000'
END cost_range
FROM gold.dim_products)

SELECT cost_range,
COUNT(product_key) AS total_product
FROM product_segment
GROUP BY cost_range
ORDER BY total_product DESC

--Group cust into 3 segment
-- vip : Cust with 12 month history and spend more than $50000
-- regular : Cust with 12 month history but spend  $50000 or less 
-- new : Cust with less than 12 month history 
--Find the totral numberof customers by each group

WITH customer_spending AS(
SELECT c.customer_key,
SUM(f.sales_amount) AS total_spending,
MIN(order_date) AS first_order,
MAX(order_date) AS last_order,
DATEDIFF(month,MIN(order_date),MAX(order_date)) AS lifespan
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
ON c.customer_key = f.customer_key
GROUP BY c.customer_key
)
SELECT customer_segment,
COUNT(customer_key) AS total_customers FROM 
(
SELECT
customer_key,
CASE WHEN lifespan >= 12 AND total_spending > 50000 THEN 'VIP'
	 WHEN lifespan >= 12 AND total_spending <= 50000 THEN 'Regular'
	 ELSE 'New'
END customer_segment
FROM customer_spending)t
GROUP BY customer_segment
ORDER BY total_customers DESC
GO


--Customizing all the above as one report

CREATE VIEW gold.report_customers AS
	WITH base_query AS(
	--Retrieves core columns from table
	SELECT 
	f.order_number,
	f.product_key,
	f.order_date,
	f.sales_amount,
	f.quantity,
	c.customer_key,
	c.customer_number,
	CONCAT(c.first_name,'',c.last_name) AS customer_name,
	DATEDIFF(year, c.birthdate,GETDATE()) age
	FROM gold.fact_sales f
	LEFT JOIN gold.dim_customers c
	ON c.customer_key = f.customer_key
	WHERE order_date IS NOT NULL

	),customer_aggregation AS (
	--Customer Aggregation 
	SELECT customer_key,
	customer_number,
	customer_name,
	age,
	COUNT(DISTINCT order_number) AS total_orders,
	SUM(sales_amount) AS total_sales,
	SUM(quantity) AS total_quantity,
	COUNT(DISTINCT product_key) AS total_products,
	MAX(order_date) AS last_order_date,
	DATEDIFF(month,MIN(order_date),MAX(order_date)) AS lifespan
	FROM base_query
	GROUP BY customer_key,
	customer_number,
	customer_name,
	age 
	)
	SELECT customer_key,
	customer_number,
	customer_name,
	age,
	CASE WHEN age < 20 THEN 'Under 20'
		 WHEN age BETWEEN 20 AND 29 THEN '20-29'
		 WHEN age BETWEEN 30 AND 39 THEN '30-23'
		 WHEN age BETWEEN 40 AND 49 THEN '40-49'
		 ELSE '50 and above'
	END AS age_group,

	CASE WHEN lifespan >= 12 AND total_sales > 50000 THEN 'VIP'
	 WHEN lifespan >= 12 AND total_sales <= 50000 THEN 'Regular'
	 ELSE 'New'
   END customer_segment,
   	last_order_date,
	DATEDIFF(month,	last_order_date,GETDATE()) AS recency,
    total_orders,
	total_sales,
	total_quantity,
	total_products,
	lifespan,
	--Average value
	CASE WHEN total_sales =  0 THEN 0
	 ELSE total_sales/total_orders 
	 END AS avg_order_value,
	 -- Avg monthly spend
	 CASE WHEN lifespan =  0 THEN total_sales
	 ELSE total_sales/lifespan 
	 END AS avg_monthly_spend
	FROM customer_aggregation
