-- Identify customers who have never rented films but have made payments.
SELECT
	se_payment.customer_id
FROM public.payment se_payment
LEFT JOIN public.rental se_rental
	ON se_payment.rental_id = se_rental.rental_id
WHERE se_rental.rental_id IS NULL


-- Determine the average number of films rented per customer, broken down by city.
WITH CTE_TOTAL_RENTALS_PER_CUSTOMER AS
(
	SELECT
		se_rental.customer_id,
		COUNT(se_rental.rental_id) AS total_film_rentals 
	FROM public.rental se_rental
	GROUP BY
		se_rental.customer_id
),

CTE_CUSTOMER_CITIES AS
(
	SELECT
		se_customer.customer_id,
		se_city.city AS city_name
	FROM public.customer se_customer
	INNER JOIN public.address se_address
		ON se_customer.address_id = se_address.address_id
	INNER JOIN public.city se_city
		ON se_city.city_id = se_address.city_id
)

SELECT
	cte_cities.city_name,
	ROUND(AVG(cte_rentals.total_film_rentals),2) AS avg_rentals
FROM CTE_TOTAL_RENTALS_PER_CUSTOMER AS cte_rentals
INNER JOIN CTE_CUSTOMER_CITIES AS cte_cities
	ON cte_rentals.customer_id = cte_cities.customer_id
GROUP BY
	cte_cities.city_name
	
-- Identify films that have been rented more than the average number of times and are currently not in inventory.
WITH CTE_TOTAL_RENTALS_PER_FILM AS
(
	SELECT
		se_film.film_id,
		se_film.title,
		se_inventory.inventory_id,
		COUNT(se_rental.rental_id) AS total_rentals
	FROM public.film se_film
	LEFT JOIN public.inventory se_inventory
		ON se_film.film_id = se_inventory.film_id
	LEFT JOIN public.rental se_rental
		ON se_rental.inventory_id = se_inventory.inventory_id
	GROUP BY
		se_film.film_id,
		se_film.title,
		se_inventory.inventory_id
)
SELECT
	film_id,
	title
FROM CTE_TOTAL_RENTALS_PER_FILM
WHERE total_rentals > (SELECT ROUND(AVG(total_rentals),2) FROM CTE_TOTAL_RENTALS_PER_FILM)
	AND inventory_id IS NULL


-- Calculate the replacement cost of lost films for each store, considering the rental history.
SELECT
	se_inventory.store_id,
	SUM(se_film.replacement_cost) AS total_replacement_cost
FROM public.film se_film
INNER JOIN public.inventory se_inventory
	ON se_film.film_id = se_inventory.film_id
INNER JOIN public.rental se_rental
	ON se_inventory.inventory_id = se_rental.inventory_id
WHERE
	se_rental.return_date IS NULL
GROUP BY
	se_inventory.store_id


-- Create a report that shows the top 5 most rented films in each category,
-- along with their corresponding rental counts and revenue.
WITH CTE_TOTAL_RENTALS AS
(
	SELECT
		se_inventory.film_id,
		COUNT(se_rental.rental_id) AS total_rentals,
		SUM(se_payment.amount) AS total_revenue
	FROM public.rental se_rental
	INNER JOIN public.inventory se_inventory
		ON se_inventory.inventory_id = se_rental.inventory_id
	INNER JOIN public.payment se_payment
		ON se_payment.rental_id = se_rental.rental_id
	GROUP BY
		se_inventory.film_id
),
CTE_FILM_RENTALS_CATEGORY AS
(
	SELECT
		se_film.film_id,
		se_film.title AS film_title,
		se_category.name AS category_name,
		CTE_TOTAL_RENTALS.total_rentals,
		CTE_TOTAL_RENTALS.total_revenue
	FROM public.film se_film
	INNER JOIN public.film_category se_film_category
		ON se_film.film_id = se_film_category.film_id
	INNER JOIN public.category se_category
		ON se_category.category_id = se_film_category.category_id
	INNER JOIN CTE_TOTAL_RENTALS
		ON CTE_TOTAL_RENTALS.film_id = se_film.film_id
)
SELECT
	category_name,
	film_title,
	total_rentals,
	total_revenue
FROM (
	SELECT
		category_name,
		film_title,
		total_rentals,
		total_revenue,
		ROW_NUMBER() OVER(PARTITION BY category_name ORDER BY total_rentals DESC)
	FROM CTE_FILM_RENTALS_CATEGORY
	) AS partitioned_films
	WHERE ROW_NUMBER <= 5


-- Develop a query that automatically updates the top 10 most frequently rented films.
CREATE VIEW top_10_most_rented AS
SELECT
	se_film.film_id,
	COUNT(se_rental.rental_id) AS total_rentals
FROM public.film se_film
LEFT JOIN public.inventory se_inventory
	ON se_film.film_id = se_inventory.film_id
LEFT JOIN public.rental se_rental
	ON se_rental.inventory_id = se_inventory.inventory_id
GROUP BY
	se_film.film_id
ORDER BY
	COUNT(se_rental.rental_id) DESC
LIMIT 10;


-- Identify stores where the revenue from film rentals exceeds the revenue from payments for all customers.
WITH CTE_REVENUE_FROM_RENTALS AS
(
	SELECT
		se_inventory.store_id,
		SUM(se_payment.amount) AS total_rental_revenue
	FROM public.rental se_rental
	INNER JOIN public.payment se_payment
		ON se_rental.rental_id = se_payment.rental_id
	INNER JOIN public.inventory se_inventory
		ON se_inventory.inventory_id = se_rental.inventory_id
	GROUP BY
		se_inventory.store_id
),
CTE_REVENUE_FROM_CUSTOMERS AS
(
	SELECT
		se_customer.store_id,
		SUM(se_payment.amount) AS total_customer_revenue
	FROM public.payment se_payment
	INNER JOIN public.customer se_customer
		ON se_payment.customer_id = se_customer.customer_id
	GROUP BY
		se_customer.store_id
)
SELECT
	cte_rental.store_id
FROM CTE_REVENUE_FROM_RENTALS cte_rental
INNER JOIN CTE_REVENUE_FROM_CUSTOMERS cte_customer
	ON cte_rental.store_id = cte_customer.store_id
WHERE cte_rental.total_rental_revenue > cte_customer.total_customer_revenue


-- Determine the average rental duration and total revenue for each store.
SELECT
	se_inventory.store_id,
	ROUND(
		AVG(EXTRACT(DAY FROM (se_rental.return_date - se_rental.rental_date)) * 24
			+ EXTRACT(HOUR FROM (se_rental.return_date - se_rental.rental_date))),2
	) AS avg_rental_duration_hrs,
	SUM(se_payment.amount) AS total_revenue
FROM public.rental se_rental
INNER JOIN public.payment se_payment
	ON se_rental.rental_id = se_payment.rental_id
INNER JOIN public.inventory se_inventory
	ON se_inventory.inventory_id = se_rental.inventory_id
GROUP BY
	se_inventory.store_id
	
	
-- Analyze the seasonal variation in rental activity and payments for each store.
WITH CTE_RENTAL_ACTIVITY AS
(
	SELECT
		CONCAT(TO_CHAR(se_rental.rental_date,'YYYY-MM')) AS year_month,
		COUNT(DISTINCT se_rental.rental_id) AS total_rentals
	FROM public.rental se_rental
	GROUP BY
		CONCAT(TO_CHAR(se_rental.rental_date,'YYYY-MM'))
),
CTE_PAYMENT_ACTIVITY AS
(
	SELECT
		CONCAT(TO_CHAR(se_payment.payment_date,'YYYY-MM')) AS year_month,
		SUM(se_payment.amount) AS total_amount
	FROM public.payment se_payment
	GROUP BY
		CONCAT(TO_CHAR(se_payment.payment_date,'YYYY-MM'))
)
SELECT
    all_months.year_month,
    COALESCE(SUM(CTE_RENTAL_ACTIVITY.total_rentals),0) AS total_rentals,
    COALESCE(SUM(CTE_PAYMENT_ACTIVITY.total_amount),0) AS total_payment
FROM (
    SELECT
		year_month
	FROM CTE_RENTAL_ACTIVITY
    UNION
    SELECT
		year_month
	FROM CTE_PAYMENT_ACTIVITY
	) AS all_months
LEFT JOIN CTE_RENTAL_ACTIVITY
	ON all_months.year_month = CTE_RENTAL_ACTIVITY.year_month
LEFT JOIN CTE_PAYMENT_ACTIVITY
	ON all_months.year_month = CTE_PAYMENT_ACTIVITY.year_month
GROUP BY
    all_months.year_month
ORDER BY
    all_months.year_month

-- ANALYSIS:
-- More rentals were made in the second half than in the first half of 2005, not much can be said about 2006.
-- Most payments were made in March and April of 2007.
