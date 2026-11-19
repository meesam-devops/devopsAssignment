# DevOpsAssessment

Small ASP.NET Core application for a DevOps practical assessment.
Requires the .NET 10 SDK to build. No additional NuGet packages or database are required.

## Build and run

From this directory:

```bash
dotnet restore
dotnet build --configuration Release
dotnet run --configuration Release --no-build --urls http://0.0.0.0:8080
```

From another terminal:

```bash
curl -f http://localhost:8080/
curl -f http://localhost:8080/health
curl -f http://localhost:8080/version
```

- GET /: JSON application information.
- GET /health: HTTP 200 and Healthy. Checks application health only.
- GET /version: JSON containing the configured version.

## Publish and run on Linux

```bash
dotnet publish --configuration Release --output ./publish
ASPNETCORE_URLS=http://0.0.0.0:8080 APP_VERSION=1.0.0 APP_MESSAGE="Assessment deployment successful" dotnet ./publish/DevOpsAssessment.dll
```

The deployment host requires the ASP.NET Core 10 runtime for this framework-dependent publish.

## Configuration

| Environment variable | Purpose | Default |
|---|---|---|
| APP_VERSION | Version reported by the API | 1.0.0 |
| APP_MESSAGE | Message returned by the home endpoint | Hello from the DevOps assessment application! |
| ASPNETCORE_URLS | Listening addresses | Framework default |
| ASPNETCORE_ENVIRONMENT | Application environment | Production |

Logs are emitted as JSON to standard output. No credentials are required.
APP_VERSION is a display value; changing it alone does not roll back application code.
Use distinct image tags or published artifacts for real release rollback.

## Candidate work

Create your own Dockerfile, Docker Compose configuration, Nginx or HAProxy
configuration, Jenkins pipeline or GitHub Actions workflow, and deployment and
rollback scripts. Keep secrets outside Git. Demonstrate health checks,
failure detection and recovery. Document HTTPS/certificate renewal and log
retention for production. Paid cloud resources are not required.

Allow 4–6 hours and document any incomplete work. AI assistance is allowed;
explain its use and be prepared to explain and modify your implementation.

## Package validation

ZIP integrity was checked. Compilation was not run in the packaging environment
because the .NET SDK was unavailable; run the build commands above locally.
