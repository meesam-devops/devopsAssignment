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
WORKDIR /app
COPY --from=build /app/publish .
# Non-root user built into Microsoft's image (UID 1654)
USER $APP_UID
EXPOSE 8080
# Healthcheck uses bash's built-in /dev/tcp: no curl, no apt-get, no network needed at build time
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8080 && printf 'GET /health HTTP/1.0\\r\\n\\r\\n' >&3 && grep -q Healthy <&3"]
ENTRYPOINT ["dotnet", "DevOpsAssessment.dll"]
grep -n "apt-get\|curl" Dockerfile || echo "OK - no apt/curl in Dockerfile"

