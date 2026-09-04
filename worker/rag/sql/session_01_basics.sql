-- ============================================================
-- SQL INTERVIEW PREP — Session 01: Basics
-- Dataset: uber_analytics → trips table (3,745 rows)
-- Date: 2026-06-01
-- Progress: SELECT → WHERE → ORDER BY → LIMIT → NULL → Aggregations
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- LESSON 1: SELECT + FROM
-- ────────────────────────────────────────────────────────────

-- Все колонки
SELECT * FROM trips;

-- Конкретные колонки
SELECT trip_id, status, original_fare_usd
FROM trips;


-- ────────────────────────────────────────────────────────────
-- LESSON 2: WHERE — фильтрация строк
-- ────────────────────────────────────────────────────────────

-- Только завершённые поездки
SELECT trip_id, status, original_fare_usd
FROM trips
WHERE status = 'completed';              -- строки чувствительны к регистру!

-- Числовой фильтр
SELECT trip_id, original_fare_usd, is_airport_trip
FROM trips
WHERE original_fare_usd > 20;


-- ────────────────────────────────────────────────────────────
-- LESSON 3: ORDER BY + LIMIT
-- ────────────────────────────────────────────────────────────

-- DESC = от большего к меньшему, ASC = от меньшего (по умолчанию)
SELECT trip_id, original_fare_usd
FROM trips
WHERE status = 'completed'
ORDER BY original_fare_usd DESC
LIMIT 10;

-- ✅ Задание выполнено: топ-5 самых дешёвых completed поездок
SELECT trip_id, status, original_fare_usd
FROM trips
WHERE status = 'completed'
ORDER BY original_fare_usd ASC
LIMIT 5;
-- Результат: все по $5.28 — минимальный тариф Uber


-- ────────────────────────────────────────────────────────────
-- LESSON 4: NULL
-- ────────────────────────────────────────────────────────────

-- NULL ≠ 0, NULL = отсутствие данных
-- Найти строки где нет fare (3 completed поездки с багом в данных!)
SELECT trip_id, status, original_fare_usd
FROM trips
WHERE original_fare_usd IS NULL;

-- IS NOT NULL — убрать строки с NULL
SELECT trip_id, status, original_fare_usd
FROM trips
WHERE original_fare_usd IS NOT NULL
ORDER BY original_fare_usd DESC
LIMIT 5;
-- Результат: 132.94 / 128.92 / 114.96 / 108.93 / 107.96

-- COALESCE — заменить NULL на другое значение (строка остаётся!)
SELECT trip_id, COALESCE(original_fare_usd, 0) AS fare
FROM trips;
-- Разница: IS NOT NULL убирает строку, COALESCE оставляет но меняет значение


-- ────────────────────────────────────────────────────────────
-- LESSON 5: Агрегатные функции COUNT / SUM / AVG / MIN / MAX
-- ────────────────────────────────────────────────────────────

-- 5 функций которые нужно знать наизусть:
-- COUNT(*) — количество строк
-- SUM(col) — сумма
-- AVG(col) — среднее
-- MIN(col) — минимум
-- MAX(col) — максимум

SELECT
    COUNT(*)                              AS total_trips,
    SUM(original_fare_usd)               AS total_earned,
    AVG(original_fare_usd)               AS avg_fare
FROM trips
WHERE status = 'completed';
-- Результат: 3,451 поездок

-- ✅ Задание: trip_count + avg + max дистанции для completed
SELECT
    COUNT(*)                             AS trip_count,
    ROUND(AVG(trip_distance_miles), 2)   AS avg_distance,
    ROUND(MAX(trip_distance_miles), 2)   AS max_distance
FROM trips
WHERE status = 'completed';


-- ────────────────────────────────────────────────────────────
-- СЛЕДУЮЩАЯ СЕССИЯ: GROUP BY
-- Вопрос: сколько поездок и средний заработок по каждому часу дня?
-- ────────────────────────────────────────────────────────────
