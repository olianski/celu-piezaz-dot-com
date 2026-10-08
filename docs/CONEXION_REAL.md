# Conexión real de Celu Piezaz Dot Com

La aplicación ya tiene roles reales en la base de datos: `technician`, `shop` y `admin`.

## Falta un paso externo
Para activar la conexión real hay que crear/usar un proyecto Supabase y proporcionar su **Project URL** y **anon public key**. No se debe subir una service_role key.

Una vez configurados esos dos valores, la aplicación podrá iniciar sesión con Supabase Auth y obtener el rol desde `public.users`.

Las migraciones 001–004 preparan perfiles, permisos RLS, inventario, pedidos y operaciones protegidas por rol.
