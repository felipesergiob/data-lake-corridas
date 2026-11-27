-- Consultas de medicao citadas no DECISOES.md. Rode cada uma no workgroup
-- eda262-gNN-athena-wg e anote QueryExecutionId e DataScannedInBytes.

-- M1 (decisao 02) chave da trusted: linhas = chaves distintas. Database: eda262_gNN_trusted
SELECT count(*) AS linhas,
       (SELECT count(*) FROM (SELECT cnpj, produto, data_coleta
                              FROM precos GROUP BY 1, 2, 3)) AS chaves_distintas
FROM precos;

-- M2 (decisao 04) mesma pergunta na trusted, COM filtro de particao. Database: eda262_gNN_trusted
SELECT uf, count(*) AS coletas, round(avg(valor_venda), 3) AS preco_medio
FROM precos
WHERE ano = '2025' AND produto = 'GASOLINA'
GROUP BY uf ORDER BY preco_medio DESC LIMIT 10;

-- M3 (decisao 04) a mesma, filtrando so por data_coleta: nao poda particao. Database: eda262_gNN_trusted
SELECT uf, count(*) AS coletas, round(avg(valor_venda), 3) AS preco_medio
FROM precos
WHERE data_coleta BETWEEN DATE '2025-01-01' AND DATE '2025-12-31' AND produto = 'GASOLINA'
GROUP BY uf ORDER BY preco_medio DESC LIMIT 10;

-- M4 (decisao 03) backfill 2024-06: 49.958 linhas esperadas. Database: eda262_gNN_trusted
SELECT count(*) AS linhas FROM precos WHERE ano = '2024' AND mes = '06';

-- M5 (decisao 01) raw x trusted no mes do backfill: 49.974 no raw. Database: eda262_gNN_raw
SELECT count(*) AS linhas_raw FROM precos_raw WHERE ano = '2024' AND mes = '06';
