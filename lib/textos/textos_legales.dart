/// Textos de las pantallas de solo lectura del Perfil (Privacidad, Términos,
/// Qué datos guardamos y Acerca de). Están aquí para poder corregirlos sin
/// tocar las pantallas. Describen lo que la app hace de verdad: ver
/// docs/deteccion.md, sección "Privacidad".
library;

/// Una sección de texto: título y párrafos (un párrafo que empieza con "• "
/// se muestra como viñeta).
typedef SeccionTexto = ({String titulo, List<String> parrafos});

// ─── Política de privacidad ─────────────────────────────────────────────

const tituloPrivacidad = 'Política de privacidad';
const avisoPrivacidad = 'Borrador – última actualización: noviembre de 2026';

const List<SeccionTexto> textoPrivacidad = [
  (
    titulo: 'Quién trata tus datos',
    parrafos: [
      'SubTrack es un proyecto académico de Programación Móvil de la Institución Universitaria de Envigado. '
          'Esta política explica qué datos usa la app y cómo los cuidamos, según la Ley 1581 de 2012 y el '
          'Decreto 1377 de 2013 (protección de datos personales en Colombia).',
    ],
  ),
  (
    titulo: 'Para qué usamos tus datos',
    parrafos: [
      'Solo para llevar el control de tus suscripciones, recordarte los cobros y, si tú lo autorizas, '
          'detectar suscripciones a partir de los avisos de cobro de tu banco.',
      'No vendemos tus datos, no los compartimos con terceros y no los usamos para publicidad. El servidor '
          'y la base de datos están alojados en proveedores de nube (Render y Neon).',
    ],
  ),
  (
    titulo: 'Qué guardamos en el servidor',
    parrafos: [
      '• Tu cuenta: nombre, correo y contraseña. La contraseña se guarda protegida (con un hash), nunca '
          'como la escribiste.',
      '• Tus suscripciones: nombre, monto, moneda, frecuencia, fechas de cobro, categoría, historial de '
          'pagos y tus preferencias de aviso.',
      '• De los pagos detectados, solo los datos extraídos: servicio o comercio, banco, monto, moneda y '
          'fecha, más una huella para no registrarlos dos veces. Solo de servicios conocidos o de cobros que '
          'se repiten. Nunca el texto del mensaje, los números de tarjeta ni teléfonos.',
      '• Si marcas una detección como "No es mía", sus pagos se guardan hasta 400 días para no volver a '
          'proponértela sin razón.',
    ],
  ),
  (
    titulo: 'Qué se queda solo en tu celular',
    parrafos: [
      '• El texto de los SMS y notificaciones de cobro: se revisa en el celular. Los que parecen un cobro '
          'esperan en un archivo interno, que solo SubTrack puede leer, hasta que se procesan (máximo 30 '
          'días).',
      '• Los pagos interpretados, incluidas las compras que no son suscripciones: cifrados, hasta 400 días. '
          'Se borran al cerrar sesión.',
      '• Las notificaciones que no son cobros (chats, correos, otras apps) se descartan sin guardarse.',
    ],
  ),
  (
    titulo: 'Permisos que usa la app',
    parrafos: [
      '• Notificaciones: para enviarte los recordatorios de cobro y los avisos de detección.',
      '• Acceso a notificaciones: para leer los avisos de cobro de tu banco y detectar suscripciones. Es '
          'opcional y lo puedes quitar cuando quieras en los ajustes de Android.',
      '• SMS (solo en la versión completa): para buscar suscripciones en tus SMS de los últimos 6 meses, '
          'solo cuando lo pides y con un permiso aparte.',
      '• Internet: para guardar tus suscripciones en el servidor.',
    ],
  ),
  (
    titulo: 'Tus derechos',
    parrafos: [
      'Como titular de tus datos puedes conocerlos, actualizarlos, rectificarlos y suprimirlos; pedir '
          'prueba de tu autorización; saber cómo se usan; revocar la autorización y presentar quejas ante la '
          'Superintendencia de Industria y Comercio.',
      'En la app puedes editar o borrar tus suscripciones, desactivar la detección y eliminar tu cuenta '
          'desde Perfil, lo que borra todos tus datos del servidor.',
    ],
  ),
  (
    titulo: 'Seguridad',
    parrafos: [
      'La app se comunica con el servidor por una conexión cifrada (HTTPS) y guarda tu sesión y los pagos '
          'locales en el almacenamiento cifrado del celular.',
    ],
  ),
  (
    titulo: 'Contacto',
    parrafos: ['Para ejercer tus derechos o resolver dudas: [correo de contacto por definir].'],
  ),
];

// ─── Términos de uso ────────────────────────────────────────────────────

const tituloTerminos = 'Términos de uso';

const List<SeccionTexto> textoTerminos = [
  (
    titulo: 'Qué es SubTrack',
    parrafos: [
      'SubTrack es una app informativa para llevar el control de tus suscripciones: cuánto cuestan, cada '
          'cuánto se cobran y cuándo es el próximo cobro.',
    ],
  ),
  (
    titulo: 'Lo que la app no hace',
    parrafos: [
      'SubTrack no hace pagos ni cancela suscripciones por ti. Las guías de cancelación te dicen los pasos, '
          'pero la cancelación la haces tú en cada servicio.',
    ],
  ),
  (
    titulo: 'Detecciones',
    parrafos: [
      'La detección automática puede equivocarse o no ver algunos cobros. Por eso cada detección te la '
          'proponemos y tú la confirmas antes de guardarla. Revisa siempre los montos y las fechas.',
    ],
  ),
  (
    titulo: 'Proyecto académico',
    parrafos: [
      'El servicio se ofrece como proyecto académico, sin costo y sin garantías de disponibilidad. El '
          'servidor puede tardar cerca de un minuto en responder si estuvo inactivo.',
      'Al usar la app aceptas estos términos y la política de privacidad.',
    ],
  ),
];

// ─── Qué datos guardamos (lenguaje simple) ──────────────────────────────

const tituloDatos = 'Qué datos guardamos';

const List<SeccionTexto> textoDatos = [
  (
    titulo: 'En nuestro servidor',
    parrafos: [
      '• Tu nombre, tu correo y tu contraseña (protegida).',
      '• Las suscripciones que agregas o confirmas, con sus pagos y tus preferencias de aviso.',
      '• De los cobros detectados, solo el servicio, el banco, el monto, la moneda y la fecha.',
    ],
  ),
  (
    titulo: 'Solo en tu celular',
    parrafos: [
      '• El texto de los SMS y notificaciones de cobro. Se revisa aquí y no sale del celular.',
      '• Las compras que no son suscripciones, cifradas, hasta 400 días.',
    ],
  ),
  (
    titulo: 'Lo que nunca guardamos',
    parrafos: [
      '• Tus chats, correos ni notificaciones de otras apps: se descartan sin leerlos ni guardarlos.',
      '• Los números de tus tarjetas ni los teléfonos que traen los mensajes.',
    ],
  ),
  (
    titulo: 'Permisos',
    parrafos: [
      '• Notificaciones: para avisarte antes de cada cobro.',
      '• Acceso a notificaciones: para detectar los cobros de tu banco. Es opcional.',
      '• SMS: solo en la versión completa y solo si pides buscar en tus SMS.',
    ],
  ),
  (
    titulo: 'Tú decides',
    parrafos: [
      'Puedes ver, corregir o borrar tus suscripciones, apagar la detección y eliminar tu cuenta con todos '
          'tus datos desde Perfil.',
    ],
  ),
];

// ─── Acerca de ──────────────────────────────────────────────────────────

const tituloAcercaDe = 'Acerca de SubTrack';
const descripcionApp = 'Lleva el control de tus suscripciones: cuánto cuestan, cada cuánto se cobran, '
    'recordatorios antes de cada cobro y guías para cancelar.';
const equipo = ['David Bustos', 'Santiago', 'Cristian'];
const creditoAcademico = 'Proyecto de Programación Móvil – Institución Universitaria de Envigado, 2026';
