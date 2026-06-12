# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY src/ConnectivityCheck.csproj ./src/
RUN dotnet restore ./src/ConnectivityCheck.csproj

COPY src/ ./src/
RUN dotnet publish ./src/ConnectivityCheck.csproj \
    --configuration Release \
    --output /app/publish \
    --no-restore

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

ENV ASPNETCORE_URLS=http://+:8080
ENV PORT=8080

EXPOSE 8080

RUN apt-get update && apt-get install -y \
    curl \
    dnsutils \
    traceroute \
    nmap \
    iputils-ping \
    iproute2 \
    python3 \
    && rm -rf /var/lib/apt/lists/*

ENV DOTNET_RUNNING_IN_CONTAINER=true

COPY --from=build /app/publish .

USER $APP_UID

ENTRYPOINT ["dotnet", "ConnectivityCheck.dll"]