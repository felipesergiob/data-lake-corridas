-- Em quais estados a gasolina comum e mais cara,
-- e os postos com bandeira cobram mais que os de bandeira branca?
-- Roda na refined (database eda262_gNN_refined). O filtro em ano (coluna de
-- particao) faz o Athena ler so as particoes de 2025.
SELECT
  uf,
  sum(coletas) AS coletas,
  round(sum(soma_valor) / sum(coletas), 3) AS preco_medio,
  round(sum(CASE WHEN tipo_bandeira = 'BRANCA' THEN soma_valor END)
      / sum(CASE WHEN tipo_bandeira = 'BRANCA' THEN coletas END), 3) AS preco_branca,
  round(sum(CASE WHEN tipo_bandeira = 'BANDEIRA' THEN soma_valor END)
      / sum(CASE WHEN tipo_bandeira = 'BANDEIRA' THEN coletas END), 3) AS preco_bandeira,
  round(sum(CASE WHEN tipo_bandeira = 'BANDEIRA' THEN soma_valor END)
      / sum(CASE WHEN tipo_bandeira = 'BANDEIRA' THEN coletas END)
      - sum(CASE WHEN tipo_bandeira = 'BRANCA' THEN soma_valor END)
      / sum(CASE WHEN tipo_bandeira = 'BRANCA' THEN coletas END), 3) AS diferenca_bandeira
FROM precos_uf_mes
WHERE ano = '2025'
  AND produto = 'GASOLINA'
GROUP BY uf
ORDER BY preco_medio DESC
LIMIT 10;
