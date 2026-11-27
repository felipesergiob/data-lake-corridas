-- M1 trusted
SELECT count(*) AS linhas,
       (SELECT count(*) FROM (SELECT cnpj, produto, data_coleta
                              FROM precos GROUP BY 1, 2, 3)) AS chaves_distintas
FROM precos;

-- M2 trusted
SELECT uf, count(*) AS coletas, round(avg(valor_venda), 3) AS preco_medio
FROM precos
WHERE ano = '2025' AND produto = 'GASOLINA'
GROUP BY uf ORDER BY preco_medio DESC LIMIT 10;

-- M3 trusted
SELECT uf, count(*) AS coletas, round(avg(valor_venda), 3) AS preco_medio
FROM precos
WHERE data_coleta BETWEEN DATE '2025-01-01' AND DATE '2025-12-31' AND produto = 'GASOLINA'
GROUP BY uf ORDER BY preco_medio DESC LIMIT 10;

-- M4 trusted
SELECT count(*) AS linhas FROM precos WHERE ano = '2024' AND mes = '06';

-- M5 raw
SELECT count(*) AS linhas_raw FROM precos_raw WHERE ano = '2024' AND mes = '06';
