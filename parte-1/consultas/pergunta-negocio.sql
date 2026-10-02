SELECT
  bairro,
  count(*) AS corridas_madrugada,
  round(sum(valor), 2) AS receita_madrugada
FROM corridas_trusted
WHERE substr(data_corrida, 12, 2) BETWEEN '00' AND '05'
  AND valor IS NOT NULL
GROUP BY bairro
ORDER BY receita_madrugada DESC
LIMIT 5;
