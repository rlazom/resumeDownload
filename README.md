# resumeDownload

resumeDownload es una aplicación de prueba de concepto escrita en Flutter que permite reanudar descargas interrumpidas y realizar descargas paralelas a partir de una URL. La aplicación utiliza la biblioteca `dio` de Flutter para realizar las solicitudes de descarga HTTP.

## Funcionalidades

- Descarga de archivos desde una URL
- Reanudación automática de descargas interrumpidas
- Descarga paralela de archivos utilizando múltiples hilos
- Verificación de integridad de archivos utilizando MD5 checksum

## Capturas de pantalla

![Captura de pantalla 1](screenshots/screenshot1.jpg)
![Captura de pantalla 2](screenshots/screenshot2.jpg)
![Captura de pantalla 2](screenshots/screenshot2.jpg)

## Requisitos

- Flutter 2.0 o posterior
- Dart 2.12 o posterior

## Instalación

1. Clone el repositorio:
```
git clone https://github.com/rlazom/resumeDownload.git
```

2. Instale las dependencias necesarias:

```
flutter pub get
```

3. Ejecute la aplicación:

```
flutter run
```

## Uso
Para descargar un archivo, simplemente ingrese la URL del archivo en el campo de entrada y presione el botón flotante "Descargar". Puede descargar un archivo en varias partes simultáneamente utilizando la funcionalidad de descarga paralela de la aplicación.

Si la descarga se interrumpe por cualquier motivo, la aplicación intentará reanudar automáticamente la descarga desde donde se detuvo utilizando la funcionalidad de reanudación de descarga.

La aplicación también verifica la integridad de los archivos descargados utilizando el valor de MD5 checksum proporcionado por el servidor.

## Contribución
Si encuentra un error o tiene una solicitud de función, abra un problema en GitHub. También se aceptan solicitudes de extracción.

## Licencia
resumeDownload se lanza bajo la Licencia MIT. Consulte LICENSE para obtener más información.