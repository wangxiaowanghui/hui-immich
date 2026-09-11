import { NestExpressApplication } from '@nestjs/platform-express';
import { json, urlencoded } from 'body-parser';
import compression from 'compression';
import cookieParser from 'cookie-parser';
import type { Request, Response } from 'express';
import helmetMiddleware from 'helmet';
import { existsSync } from 'node:fs';
import sirv from 'sirv';
import { IMMICH_SERVER_START, excludePaths, serverVersion } from 'src/constants';
import { MaintenanceWorkerService } from 'src/maintenance/maintenance-worker.service';
import { WebSocketAdapter } from 'src/middleware/websocket.adapter';
import { ConfigRepository } from 'src/repositories/config.repository';
import { LoggingRepository } from 'src/repositories/logging.repository';
import { bootstrapTelemetry } from 'src/repositories/telemetry.repository';
import { ApiService } from 'src/services/api.service';
import { useSwagger } from 'src/utils/misc';

export function configureTelemetry() {
  const { telemetry } = new ConfigRepository().getEnv();
  if (telemetry.metrics.size > 0) {
    bootstrapTelemetry(telemetry.apiPort);
  }
}

export async function configureExpress(
  app: NestExpressApplication,
  {
    permitSwaggerWrite = true,
    ssr,
  }: {
    /**
     * Whether to allow swagger module to write to the specs.json
     * This is not desirable when the API is not available
     * @default true
     */
    permitSwaggerWrite?: boolean;
    /**
     * Service to use for server-side rendering
     */
    ssr: typeof ApiService | typeof MaintenanceWorkerService;
  },
) {
  const configRepository = app.get(ConfigRepository);
  const { environment, host, port, helmet, resourcePaths, network } = configRepository.getEnv();

  const logger = await app.resolve(LoggingRepository);
  logger.setContext('Bootstrap');
  app.useLogger(logger);

  app.set('trust proxy', ['loopback', ...network.trustedProxies]);
  app.set('etag', 'strong');

  if (helmet.config) {
    app.use(helmetMiddleware(helmet.config));
    logger.log('Initialized helmet middleware');
  }

  app.use(cookieParser());
  app.use(json({ limit: '10mb' }));
  app.use(urlencoded({ limit: '10mb' }));

  if (configRepository.isDev()) {
    app.enableCors();
  }

  configureAmapProxy(app, configRepository, logger);

  app.setGlobalPrefix('api', { exclude: excludePaths });
  app.useWebSocketAdapter(new WebSocketAdapter(app));

  useSwagger(app, { write: configRepository.isDev() && permitSwaggerWrite });

  if (existsSync(resourcePaths.web.root)) {
    // copied from https://github.com/sveltejs/kit/blob/679b5989fe62e3964b9a73b712d7b41831aa1f07/packages/adapter-node/src/handler.js#L46
    // provides serving of precompressed assets and caching of immutable assets
    app.use(
      sirv(resourcePaths.web.root, {
        etag: true,
        gzip: true,
        brotli: true,
        extensions: [],
        setHeaders: (res, pathname) => {
          if (pathname.startsWith(`/_app/immutable`) && res.statusCode === 200) {
            res.setHeader('cache-control', 'public,max-age=31536000,immutable');
          }
        },
      }),
    );
  }

  app.use(app.get(ssr).ssr(excludePaths));
  app.use(compression());

  const server = await (host ? app.listen(port, host) : app.listen(port));
  server.requestTimeout = 24 * 60 * 60 * 1000;

  logger.log(`${IMMICH_SERVER_START} on ${await app.getUrl()} [v${serverVersion}] [${environment}] `);
}

function configureAmapProxy(
  app: NestExpressApplication,
  configRepository: ConfigRepository,
  logger: LoggingRepository,
) {
  const { amap } = configRepository.getEnv();
  const webSecurityJsCode = amap?.webSecurityJsCode;
  if (!amap?.webKey || !webSecurityJsCode) {
    return;
  }

  const prefix = '/_AMapService';
  app.use(prefix, async (request: Request, response: Response) => {
    if (request.method !== 'GET') {
      response.sendStatus(405);
      return;
    }

    const suffix = request.originalUrl.slice(prefix.length);
    if (!/^\/(?!\/)[\w!$&'()*+,./:;=@%~-]+(?:\?[\s\S]*)?$/.test(suffix)) {
      response.sendStatus(400);
      return;
    }

    const upstreamUrl = new URL(suffix, 'https://restapi.amap.com');
    upstreamUrl.searchParams.set('jscode', webSecurityJsCode);

    try {
      const upstream = await fetch(upstreamUrl, {
        headers: { accept: request.header('accept') || '*/*' },
        redirect: 'error',
        signal: AbortSignal.timeout(15_000),
      });
      response.status(upstream.status);
      const contentType = upstream.headers.get('content-type');
      if (contentType) {
        response.setHeader('content-type', contentType);
      }
      const cacheControl = upstream.headers.get('cache-control');
      if (cacheControl) {
        response.setHeader('cache-control', cacheControl);
      }
      response.send(Buffer.from(await upstream.arrayBuffer()));
    } catch (error) {
      logger.warn(`AMap proxy request failed: ${error instanceof Error ? error.message : 'unknown error'}`);
      response.sendStatus(502);
    }
  });
}
