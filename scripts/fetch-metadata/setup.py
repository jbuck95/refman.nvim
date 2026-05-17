from setuptools import setup, find_packages

setup(
    name="fetch-metadata",
    version="0.1",
    packages=find_packages("src"),
    package_dir={"": "src"},
    install_requires=[
        "requests>=2.28.0",
        "beautifulsoup4>=4.11.0",
        "lxml>=4.9.0",
        "isbnlib>=0.9.0",
    ],
    entry_points={
        "console_scripts": [
            "fetch-metadata=metadata.cli:main",  # Changed from cli:main to metadata.cli:main
        ]
    }
)
