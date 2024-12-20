import aiohttp
import asyncio
import logging
from typing import List, Dict
from bs4 import BeautifulSoup
from urllib.parse import urljoin

PYPI_URL = "http://<Path to ALB>/repository/python/simple"

PACKAGE_LIST_URL = "https://cdn.jsdelivr.net/gh/hugovk/top-pypi-packages/top-pypi-packages-30-days.min.json"
CONCURRENCY = 5

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class PyPiPackageFetcher:
    def __init__(self, concurrent_downloads: int = 5):
        self.concurrent_downloads = concurrent_downloads

    async def fetch_package_list(self, session: aiohttp.ClientSession) -> List[Dict]:
        """Fetch list of top PyPI packages"""
        try:
            logger.info("Fetching package list from hugovk.github.io...")
            async with session.get(PACKAGE_LIST_URL) as response:
                if response.status == 200:
                    try:
                        data = await response.json()
                        packages = [{"name": pkg["project"]} for pkg in data["rows"]]
                        logger.info(f"Retrieved {len(packages)} packages")
                        return packages
                    except Exception as e:
                        logger.error(f"Error parsing JSON: {e}")
                        return []
                else:
                    logger.error(f"Failed to fetch package list: {response.status}")
                    return []

        except Exception as e:
            logger.error(f"Error fetching package list: {e}")
            return []

    async def download_package(self, session: aiohttp.ClientSession, package: Dict) -> None:
        """Download a wheel file for a PyPI package using simple API"""
        name = package["name"]
        package_url = f"{PYPI_URL}/{name}/"

        try:
            # Get package page from simple API
            logger.info(f"Fetching package page for {name}")
            async with session.get(package_url) as response:
                if response.status == 200:
                    html_content = await response.text()
                    soup = BeautifulSoup(html_content, 'html.parser')

                    # Find all package files
                    files = []
                    for anchor in soup.find_all('a'):
                        href = anchor.get('href', '')
                        if ".whl" in href:
                            # Handle relative URLs and remove query parameters and hash fragments
                            clean_url = href.split('#')[0].split('?')[0]
                            # Resolve relative URLs against the package URL
                            absolute_url = urljoin(package_url, clean_url)
                            files.append({
                                'url': absolute_url,
                                'requires_python': anchor.get('data-requires-python'),
                                'filename': clean_url.split('/')[-1]
                            })

                    if files:
                        # Download the first available wheel file
                        wheel_file = files[0]
                        wheel_url = wheel_file['url']
                        logger.info(f"Downloading wheel for {name}: {wheel_file['filename']}")
                        async with session.get(wheel_url) as wheel_response:
                            if wheel_response.status == 200:
                                await wheel_response.read()  # Read to warm up the mirror
                                logger.info(f"Downloaded wheel for {name}")
                            else:
                                logger.error(f"Failed to download wheel for {name}: {wheel_response.status}")
                    else:
                        # If no wheel files found, just warm up the package page
                        logger.warning(f"No wheel files found for {name}")
                        logger.info(f"Downloaded simple index for {name} (no wheel available)")
                else:
                    logger.error(f"Failed to fetch package page for {name}: {response.status}")
        except Exception as e:
            logger.error(f"Error processing {name}: {e}")

    async def run(self) -> None:
        """Main execution method"""
        async with aiohttp.ClientSession() as session:
            logger.info("Fetching package list...")
            packages = await self.fetch_package_list(session)

            if packages:
                logger.info(f"Found {len(packages)} packages. Starting downloads...")
                tasks = [
                    asyncio.create_task(self.download_package(session, package))
                    for package in packages
                ]

                # Process in batches to limit concurrency
                for i in range(0, len(tasks), self.concurrent_downloads):
                    batch = tasks[i:i + self.concurrent_downloads]
                    await asyncio.gather(*batch)

                logger.info("All packages processed")
            else:
                logger.error("No packages found")

async def main():
    fetcher = PyPiPackageFetcher(concurrent_downloads=CONCURRENCY)
    await fetcher.run()

if __name__ == "__main__":
    asyncio.run(main())
