-- 001: esquema inicial (fase 1, autenticación).
--
-- Es el mismo esquema que se creó a mano al comenzar el proyecto. En una BD
-- que ya tiene la tabla usuarios, `npm run db:migrate` marca esta migración
-- como aplicada SIN ejecutarla (ver db/migrar.js).

CREATE TABLE usuarios (
  id            SERIAL PRIMARY KEY,
  nombre        VARCHAR(100) NOT NULL,
  correo        VARCHAR(150) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  creado_en     TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE suscripciones (
  id                  SERIAL PRIMARY KEY,
  usuario_id          INT           NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  nombre              VARCHAR(100)  NOT NULL,
  precio              NUMERIC(12,2) NOT NULL CHECK (precio >= 0),
  moneda              VARCHAR(3)    NOT NULL DEFAULT 'COP',
  ciclo               VARCHAR(10)   NOT NULL CHECK (ciclo IN ('mensual', 'anual')),
  fecha_proximo_cobro DATE          NOT NULL,
  dias_aviso          INT           NOT NULL DEFAULT 3,
  activa              BOOLEAN       NOT NULL DEFAULT TRUE,
  creado_en           TIMESTAMP     NOT NULL DEFAULT NOW()
);
