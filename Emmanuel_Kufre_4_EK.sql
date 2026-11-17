
SELECT DB_NAME() AS CurrentDatabase;
GO

/* QUESTION 1
   Add discount DECIMAL(3,2), NOT NULL, default 0.00.
*/
IF COL_LENGTH('dbo.Subscriber', 'discount') IS NULL
BEGIN
    ALTER TABLE dbo.Subscriber
    ADD discount DECIMAL(3,2) NOT NULL
        CONSTRAINT DF_Subscriber_discount DEFAULT (0.00);
END;
GO

SELECT TOP 10 discount
FROM dbo.Subscriber;
GO

/* QUESTION 2
   Add email VARCHAR(50), allowing NULL.
   This is safe to run if the column already exists.
*/
IF COL_LENGTH('dbo.Person', 'email') IS NULL
BEGIN
    ALTER TABLE dbo.Person
    ADD email VARCHAR(50) NULL;
END;
GO

SELECT TOP 10 email
FROM dbo.Person;
GO

/* QUESTION 3
   Create EK_Domain (initials EK included).
*/
IF OBJECT_ID('dbo.EK_Domain', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EK_Domain
    (
        domainID INT IDENTITY(1,1) PRIMARY KEY,
        domainName VARCHAR(15)
    );
END;
GO

/* QUESTION 4
   Insert the four required domains, avoiding duplicates.
*/
INSERT INTO dbo.EK_Domain (domainName)
SELECT v.domainName
FROM (VALUES
    ('gmail.com'),
    ('yahoo.com'),
    ('hotmail.com'),
    ('eif.viko.lt')
) AS v(domainName)
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.EK_Domain AS d
    WHERE d.domainName = v.domainName
);
GO

SELECT *
FROM dbo.EK_Domain;
GO

/* QUESTION 5
   Assign firstname.lastname@random-domain to each Person.
   ASSUMPTION: Person columns are firstName and lastName.
   If your column names differ, replace them below before running.
*/
UPDATE p
SET email =
    LOWER(LTRIM(RTRIM(p.firstName))) + '.' +
    LOWER(LTRIM(RTRIM(p.lastName))) + '@' +
    d.domainName
FROM dbo.Person AS p
CROSS APPLY
(
    SELECT TOP 1 domainName
    FROM dbo.EK_Domain
    ORDER BY NEWID()
) AS d;
GO

SELECT TOP 20 firstName, lastName, email
FROM dbo.Person;
GO

/* QUESTION 6
   Create EK_MobilePhone (initials EK included).
*/
IF OBJECT_ID('dbo.EK_MobilePhone', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EK_MobilePhone
    (
        mobTelID INT IDENTITY(1,1) PRIMARY KEY,
        manufacturer VARCHAR(15),
        model VARCHAR(30),
        price FLOAT,
        monthlyPrice FLOAT
    );
END;
GO

SELECT *
FROM dbo.EK_MobilePhone;
GO

/* QUESTION 7
   Add nullable mobTelID to Subscriber.
*/
IF COL_LENGTH('dbo.Subscriber', 'mobTelID') IS NULL
BEGIN
    ALTER TABLE dbo.Subscriber
    ADD mobTelID INT NULL;
END;
GO

/* QUESTION 8
   Create foreign key from Subscriber to EK_MobilePhone.
*/
IF NOT EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_Subscriber_EK_MobilePhone'
)
BEGIN
    ALTER TABLE dbo.Subscriber
    ADD CONSTRAINT FK_Subscriber_EK_MobilePhone
    FOREIGN KEY (mobTelID)
    REFERENCES dbo.EK_MobilePhone(mobTelID);
END;
GO

SELECT name
FROM sys.foreign_keys
WHERE name = 'FK_Subscriber_EK_MobilePhone';
GO

/* QUESTION 9
   Import mobilephone.txt through a staging table because the file contains
   a blank mobTelID field, while EK_MobilePhone.mobTelID is IDENTITY.

   The file must already be copied into the SQL Server container at:
   /var/opt/mssql/data/mobilephone.txt

   This staging table is intentionally separate from the final table.
*/
IF OBJECT_ID('dbo.EK_MobilePhone_Stage', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.EK_MobilePhone_Stage
    (
        mobTelID VARCHAR(20),
        manufacturer VARCHAR(15),
        model VARCHAR(30),
        price VARCHAR(30),
        monthlyPrice VARCHAR(30)
    );
END;
GO

/* Clear staging rows so a fresh BULK INSERT does not append old staging data.
   This does NOT delete records from EK_MobilePhone.
*/
TRUNCATE TABLE dbo.EK_MobilePhone_Stage;
GO

BULK INSERT dbo.EK_MobilePhone_Stage
FROM '/var/opt/mssql/data/mobilephone.txt'
WITH
(
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    TABLOCK
);
GO

SELECT *
FROM dbo.EK_MobilePhone_Stage;
GO

/* Transfer staging rows into the final table only if it is empty.
   If EK_MobilePhone already contains records, this block stops rather than
   creating duplicate phone records. Check the table before proceeding.
*/
IF NOT EXISTS (SELECT 1 FROM dbo.EK_MobilePhone)
BEGIN
    INSERT INTO dbo.EK_MobilePhone
        (manufacturer, model, price, monthlyPrice)
    SELECT
        LTRIM(RTRIM(manufacturer)),
        LTRIM(RTRIM(model)),
        TRY_CONVERT(FLOAT, LTRIM(RTRIM(price))),
        TRY_CONVERT(FLOAT, LTRIM(RTRIM(REPLACE(monthlyPrice, CHAR(13), ''))))
    FROM dbo.EK_MobilePhone_Stage
    WHERE NULLIF(LTRIM(RTRIM(manufacturer)), '') IS NOT NULL;
END
ELSE
BEGIN
    PRINT 'EK_MobilePhone already contains records. Import was not repeated.';
END;
GO

SELECT COUNT(*) AS TotalMobilePhones
FROM dbo.EK_MobilePhone;
GO

SELECT *
FROM dbo.EK_MobilePhone;
GO

/* QUESTION 10
   Assign a random phone to subscribers whose contract end date is NULL.
   ASSUMPTION: the Subscriber date column is named contractEndDate.
   Replace this name if your schema uses a different column name.

   This updates only eligible subscribers that do not already have a mobTelID,
   preventing a repeated run from randomly reassigning their phones.
*/
UPDATE s
SET mobTelID = m.mobTelID
FROM dbo.Subscriber AS s
CROSS APPLY
(
    SELECT TOP 1 mobTelID
    FROM dbo.EK_MobilePhone
    ORDER BY NEWID()
) AS m
WHERE s.contractEndDate IS NULL
  AND s.mobTelID IS NULL;
GO

SELECT
    s.mobTelID,
    s.contractEndDate,
    m.manufacturer,
    m.model,
    m.price,
    m.monthlyPrice
FROM dbo.Subscriber AS s
LEFT JOIN dbo.EK_MobilePhone AS m
    ON s.mobTelID = m.mobTelID
WHERE s.contractEndDate IS NULL;
GO

/* FINAL VERIFICATION */
SELECT
    (SELECT COUNT(*) FROM dbo.EK_Domain) AS DomainCount,
    (SELECT COUNT(*) FROM dbo.EK_MobilePhone) AS MobilePhoneCount,
    (SELECT COUNT(*) FROM dbo.Person WHERE email IS NOT NULL) AS PeopleWithEmail;
GO

SELECT name
FROM sys.foreign_keys
WHERE name = 'FK_Subscriber_EK_MobilePhone';
GO
