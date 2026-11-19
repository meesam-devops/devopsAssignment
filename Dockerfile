# ---- Stage 1: build (has the SDK, big image, thrown away) ----
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY DevOpsAssessment.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app/publish --no-restore

# ---- Stage 2: runtime (small, only the ASP.NET runtime) ----
FROM mcr.microsoft.com/dotnet/aspnet:10.0
ARG BUILD_VERSION=dev
LABEL org.opencontainers.image.title="devops-assessment" \
      org.opencontainers.image.version="${BUILD_VERSION}"
# curl is only used for the container healthcheck
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/publish .
# Non-root user built into Microsoft's image (UID 1654)
USER $APP_UID
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://localhost:8080/health || exit 1
ENTRYPOINT ["dotnet", "DevOpsAssessment.dll"]
