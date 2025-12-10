@echo off
REM Test runner script for Windows

echo Running Exchange Service Tests
echo ==============================

REM Check if we're in the backend directory
if not exist pytest.ini (
    echo Error: Please run this script from the backend directory
    exit /b 1
)

REM Run unit tests
echo.
echo Running Unit Tests...
echo -------------------
pytest ingest/test_lambda_function.py matcher/test_lambda_function.py -v

REM Run with coverage if pytest-cov is installed
python -c "import pytest_cov" 2>nul
if %errorlevel% == 0 (
    echo.
    echo Running Tests with Coverage...
    echo ----------------------------
    pytest ingest/test_lambda_function.py matcher/test_lambda_function.py --cov=ingest --cov=matcher --cov-report=html --cov-report=term-missing
    echo.
    echo Coverage report generated in htmlcov\index.html
)

REM Check if LocalStack is running for integration tests
docker ps | findstr localstack >nul
if %errorlevel% == 0 (
    echo.
    echo LocalStack detected. Running Integration Tests...
    echo ------------------------------------------------
    pytest test_integration.py -v -m integration
) else (
    echo.
    echo Skipping Integration Tests (LocalStack not running)
    echo Start LocalStack with: docker-compose up -d
)

echo.
echo Tests Complete!

