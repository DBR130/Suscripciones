-- 003: categoría de la suscripción (design/subtrack-pantallas.md).
--
-- Es opcional (NULL = sin categoría) y solo admite las categorías que usa el
-- diseño. Para agregar otra, crea una migración nueva que cambie el CHECK.

ALTER TABLE suscripciones
  ADD COLUMN categoria VARCHAR(30) NULL
    CONSTRAINT suscripciones_categoria_check
    CHECK (categoria IN (
      'Streaming', 'Música', 'Cloud gaming', 'Almacenamiento',
      'Gimnasio', 'Software', 'Diseño'
    ));
