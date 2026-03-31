# Last-Mile Delivery Performance & Freight Optimization at Olist

## Project Background

Olist is a Brazilian e-commerce marketplace that connects small and medium businesses to customers across all 27 states. Unlike a traditional retailer, Olist does not hold inventory or operate warehouses — sellers list products on the platform and fulfill orders directly, shipping through logistics partners. This distributed model means delivery performance is a function of three independent variables: how fast the seller processes the order, how efficiently the carrier moves the package, and how far the package has to travel.

This project analyzes **96,478 delivered orders** placed between **January 2017 and August 2018** to identify where and why deliveries fail, what drives freight costs, and which sellers need operational intervention. The analysis is conducted from the perspective of a supply chain analyst on Olist's operations team, tasked with reducing late deliveries and freight inefficiency.

Insights and recommendations are provided on the following key areas:

- **Delivery Lead Time Decomposition:** Breaking total delivery time into seller processing, carrier transit, and estimation accuracy to isolate the controllable bottleneck.
- **Freight Cost Drivers:** Modeling how product weight, shipping distance, and product category interact to determine freight charges — and where the pricing structure penalizes certain segments.
- **Seller Fulfillment Efficiency:** Segmenting 2,970 active sellers by processing speed, volume, and reliability to identify who drags down platform-wide metrics.
- **Geographic Supply-Demand Imbalance:** Mapping the concentration of sellers (60% in São Paulo) against nationwide customer demand to quantify how geography drives both cost and delay.

The SQL queries used to inspect and clean the data for this analysis can be found here [link].

Targeted SQL queries regarding various business questions can be found here [link].

An interactive Power BI dashboard used to report and explore delivery and freight trends can be found here [link].


---


## Data Structure & Initial Checks

Olist's database consists of **8 interconnected tables** with approximately **1.05 million total records**. The data model follows a transactional structure centered on orders, with supporting dimension-style tables for customers, sellers, products, and geography.

- **orders** (99,441 records): The central table. Contains the full order lifecycle: purchase timestamp, approval timestamp, carrier handoff date, actual delivery date, and estimated delivery date. Each row is one order tied to one customer.
- **order_items** (112,650 records): Line-item detail linking orders to products and sellers. Contains price, freight value, and shipping limit date. A single order can contain multiple items from different sellers.
- **products** (32,951 records): Product catalog with category, weight (grams), and dimensions (length, height, width in cm). Physical attributes are the primary freight cost drivers.
- **sellers** (3,095 records): Seller registry with city, state, and zip code prefix. Seller geography determines shipment origin.
- **customers** (99,441 records): Customer registry with city, state, and zip code prefix. Customer geography determines destination.
- **reviews** (104,719 records): Post-delivery review scores (1–5) with optional comment text. The primary proxy for customer satisfaction with delivery.
- **payments** (103,886 records): Payment method, installment count, and value per order.
- **geolocation** (~1,000,000 records): Latitude and longitude mapped to zip code prefixes across Brazil, enabling seller-to-customer distance calculations.

The data warehouse was modeled as a star schema with two fact tables — **fact_deliveries** (one row per delivered order with time decomposition and review score) and **fact_order_economics** (one row per order line item with price, freight, and distance) — supported by dimension tables for seller, customer, product, date, and geography.

[Entity Relationship Diagram here]


---


## Executive Summary

### Overview of Findings

Olist delivers 91.9% of orders on time, but the 8.1% that arrive late receive devastatingly poor reviews — averaging 2.57 stars versus 4.29 for on-time orders, with 46% of late deliveries receiving 1-star ratings. The root cause is structural, not operational: 60% of sellers are concentrated in São Paulo while customers span all 27 states, creating long-haul corridors where average delivery takes 21 days and freight costs triple. Freight pricing compounds the problem — lightweight items under 500g pay an effective freight rate of 41% of product value due to minimum freight floors, while the same rate is just 6% for high-value electronics. The most actionable lever is seller processing speed: the median seller hands off to the carrier in 1.8 days, but the 90th percentile takes 6+ days, suggesting that a targeted intervention on the slowest 10% of sellers could materially reduce late deliveries without any changes to carrier operations.

[Dashboard overview screenshot]


---


## Insights Deep Dive

### Delivery Lead Time Decomposition

* **The average order takes 12.6 days from purchase to delivery, but the system promises 23.7 days on average.** This means most orders arrive 11 days early. The estimation model is systematically overpadded for short-haul routes, which masks the fact that long-haul deliveries genuinely struggle — and gives customers a false sense of when to expect trouble.

* **Seller processing (approval to carrier handoff) takes a median of 1.8 days, but the 90th percentile is 6.0 days.** This long tail means 1 in 10 orders sits idle at the seller for nearly a week before entering the carrier network. For late orders, seller-side delay is the largest controllable component — it is the one stage where Olist can intervene directly through seller SLAs and performance incentives.

* **Carrier transit (carrier pickup to customer delivery) takes a median of 7.1 days, with a 90th percentile of 18.9 days.** The wide spread reflects Brazil's geographic reality: intra-state packages arrive in 3–5 days, while packages crossing 2,000+ km corridors take 3+ weeks. This is the hardest component to compress without infrastructure investment.

* **Late delivery spikes are not random — they cluster around November 2017 (14.3%) and February–March 2018 (16–21%).** November aligns with Black Friday / holiday volume surges overwhelming seller and carrier capacity. February–March aligns with Carnival and post-holiday backlogs. These are predictable demand peaks where pre-positioning inventory or tightening seller SLAs could prevent annual recurring failures.

[Visualization: Delivery time decomposition stacked bar by distance bucket + monthly late rate line chart]


### Freight Cost Drivers

* **Freight cost scales with distance in clear steps: R$11.75 avg for <100km, R$18.34 for 100–500km, R$21.08 for 500–1,000km, R$29.23 for 1,000–2,000km, and R$35.92 for 2,000+km.** The relationship is roughly linear at R$0.012 per additional kilometer, but with a significant fixed-cost floor around R$12–15 regardless of distance, which disproportionately burdens short-distance, low-value shipments.

* **Products under 500g represent 42% of all items shipped but pay an average freight-to-price ratio of 41.5%.** This is nearly double the ratio for items over 2kg (20–26%). The minimum freight floor creates a perverse incentive structure where lightweight, inexpensive products are the most penalized by shipping costs — categories like electronics accessories (68% freight ratio), Christmas supplies (68%), and telephony accessories (51%) are most affected.

* **Freight-to-price ratio varies 12x across categories, from 6% for computers to 68% for electronics accessories.** This is not just a weight effect — it reflects the interaction between product value, weight, and distance. Low-value items shipped long distances face a double penalty, while high-value, heavy items (computers, home appliances) have freight ratios that customers barely notice.

* **Same-state shipments average R$13.20 freight vs R$22.40 for cross-state, but 64% of all order items cross state lines.** The marketplace's structure inherently generates cross-state logistics because seller supply is concentrated in a few states while demand is national. This structural mismatch inflates the platform's average freight cost by an estimated 25–30% compared to a scenario with regionally distributed sellers.

[Visualization: Freight by distance bucket step chart + category freight ratio bubble chart]


### Seller Fulfillment Efficiency

* **58% of sellers (1,732 out of 2,970) handled fewer than 10 orders during the entire analysis period.** These micro-sellers average 3.5 days of processing time versus 2.6 days for sellers with 100+ orders. The long tail of low-volume sellers likely lacks dedicated fulfillment workflows, contributing to inconsistent platform-wide delivery times.

* **The median seller processes orders in 1.8 days, but the mean is pulled up by a heavy right tail.** The distribution is not normal — it is right-skewed with a cluster of fast sellers (0–2 days) and a long tail extending past 10 days. This means platform-wide averages are misleading; the experience depends heavily on which seller fulfills the order.

* **60% of all sellers are based in São Paulo, creating both a strength and a vulnerability.** Strength: SP-origin shipments to SP customers (roughly 25% of volume) are fast and cheap. Vulnerability: any disruption to the SP logistics hub (strikes, weather, carrier outages) impacts more than half of all active sellers simultaneously. The North, Northeast, and Central-West regions collectively host fewer than 5% of sellers but represent 20%+ of customer demand.

* **Same-state orders have a 6.0% late rate and average 7.9 delivery days, while cross-state orders have a 9.0% late rate and average 15.0 days.** This 50% increase in late rate is not solely due to distance — it also reflects different carrier routing, hub-and-spoke transfers, and the compounding of seller processing delays with longer transit windows.

[Visualization: Seller processing time distribution + seller state concentration map]


### Geographic Supply-Demand Imbalance

* **Alagoas (24.0%), Maranhão (19.7%), and Piauí (16.0%) have the highest late delivery rates — 3x to 4x worse than São Paulo's 5.7%.** These Northeastern states are the farthest from the SP-concentrated seller base, with average delivery distances exceeding 2,000 km. The late delivery problem is fundamentally a geography problem.

* **Average delivery time ranges from 8 days for intra-SP orders to 24.5 days for orders to Alagoas.** Customers in the Northeast and North wait 2–3x longer than customers in the Southeast — a service inequality that directly maps to the seller-customer distance distribution.

* **Orders traveling 2,000+ km represent only 5.7% of volume but account for a disproportionate share of 1-star reviews.** These are the orders where the estimation model is least accurate, the carrier transit is longest, and the customer expectation gap is widest. They are also the most expensive to ship (R$35.92 avg freight), compounding the poor experience with high cost.

* **The top 5 customer states (SP, RJ, MG, RS, PR) account for 77% of orders and are all in the South/Southeast — close to the seller base.** The remaining 22 states share 23% of volume with significantly worse delivery metrics. This concentration means Olist's aggregate KPIs look healthy, but the experience for customers outside the Southeast corridor is materially degraded.

[Visualization: Customer state choropleth (late rate heatmap) + delivery days by customer state bar chart]


---


## Recommendations

Based on the insights and findings above, we recommend the Operations and Logistics team consider the following:

* Late deliveries concentrate on Southeast-to-North/Northeast corridors where carrier transit exceeds 15 days, and the estimation model underperforms. **Add 3–5 buffer days to estimated delivery dates for shipments crossing more than 1,000 km (representing 15.7% of volume) — this single change could reclassify 30–40% of current "late" deliveries as on-time without changing any physical operations, immediately improving review scores in the most affected states.**

* The 90th percentile seller takes 6+ days for carrier handoff, while the median is 1.8 days. Seller processing is the only stage Olist directly controls. **Implement a 48-hour handoff SLA for all sellers, with escalating warnings at 24h and 36h. For the bottom 10% of sellers by processing speed, require a fulfillment improvement plan or face reduced search visibility — this intervention targets the most impactful, lowest-cost lever in the delivery chain.**

* Lightweight items under 500g face a 41% freight-to-price ratio due to minimum freight floors, compared to 21% for items in the 2–5kg range. **Negotiate a small-parcel flat-rate tier with carrier partners for packages under 500g (42% of volume), targeting a R$8–10 price point instead of the current R$15.23 average — this could unlock demand in price-sensitive categories like accessories and telephony where freight currently exceeds 50% of product value.**

* Northern and Northeastern states represent 20%+ of customer demand but host less than 5% of sellers, forcing 2,000+ km shipments that cost R$35.92 and take 21+ days. **Launch a seller recruitment program targeting top-5 underserved states (BA, CE, PA, MA, AL) with onboarding subsidies and logistics support — even a 10% shift in seller distribution could reduce average delivery distance by 200–300 km for affected regions, cutting both freight costs and delivery times.**

* The November 2017 (14.3%) and February–March 2018 (16–21%) late delivery spikes are predictable seasonal events tied to Black Friday and Carnival. **Establish a pre-peak readiness protocol: 30 days before known demand peaks, require sellers to pre-clear inventory for faster processing, negotiate surge carrier capacity, and temporarily extend estimated delivery windows by 2–3 days to absorb volume spikes without SLA failures.**


---


## Assumptions and Caveats

Throughout the analysis, multiple assumptions were made to manage challenges with the data. These assumptions and caveats are noted below:

* Orders from 2016 (~300 records) were excluded from all trend and performance analyses due to insufficient volume during Olist's platform launch phase. The analysis window is January 2017 through August 2018.

* 1,234 orders with status "canceled" or "unavailable" (1.2% of total) were excluded from delivery performance metrics but were examined separately for cancellation root-cause analysis.

* Seller-to-customer distances were computed using haversine distance between zip code prefix centroids, not actual road distances. Real shipping distances may be 20–40% longer due to road routing, meaning freight cost efficiency calculations are conservative.

* Freight values in the dataset represent the amount charged to the customer, not the cost paid by the seller to the carrier. Seller-side logistics costs, margins on freight, and any platform subsidies are unknown and not modeled.

* Product category translations use the provided Portuguese-to-English mapping. 610 products with no English translation were grouped under "other" in category-level analyses and excluded from category-specific freight ratio rankings.

* The review score analysis assumes review scores primarily reflect delivery experience. In reality, scores also capture product quality, accuracy, and other factors. The correlation between late delivery and low scores is strong (4.29 vs 2.57 avg) but cannot be interpreted as purely causal without controlling for confounders.
