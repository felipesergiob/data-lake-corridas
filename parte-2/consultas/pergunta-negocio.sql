-- Em quais estados a gasolina comum e mais cara,
-- e os postos com bandeira cobram mais que os de bandeira branca?
SELECT
  uf,
  count(*) AS coletas,
  round(avg(valor_venda), 3) AS preco_medio,
  round(avg(CASE WHEN bandeira = 'BRANCA' THEN valor_venda END), 3) AS preco_branca,
  round(avg(CASE WHEN bandeira <> 'BRANCA' THEN valor_venda END), 3) AS preco_bandeira,
  round(avg(CASE WHEN bandeira <> 'BRANCA' THEN valor_venda END)
      - avg(CASE WHEN bandeira = 'BRANCA' THEN valor_venda END), 3) AS diferenca_bandeira
FROM precos_trusted
WHERE produto = 'GASOLINA'
  AND data_coleta BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
GROUP BY uf
ORDER BY preco_medio DESC
LIMIT 10;
