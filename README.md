Purpose: This app is part of a food allergy treatment program called the Tolerance Induction Program (TIPs). The program prescribes medicine and foods that need to be taken/eaten daily to decrease food allergies. By the end of the program, the patient can consume the foods they were once allergic to. 
Cycle: The program is split into multiple cycles. The cycle lengths vary throughout the program and are measured in weeks. Each cycle incorporates the categories below:
Category Structure: There are four categories that the patient needs to track daily. We will call the medicine or food contained within each category an item.
Medicine: Medicine (example is an antihistamine) needs to be taken daily.
Maintenance Food: These are foods that have been “cleared” by the program as safe and need to be consumed daily. This list will vary over time as foods are added and deleted from the Maintenance Food list. The daily dosage of these foods remains constant throughout each cycle. 
Treatment Foods: These are foods that are actively being worked on and need to be taken daily. The dosages of these foods vary and will increase every week. The user will know what dosage is to be taken each week of the cycle, so we can input all weekly doses these at the start of a cycle. 
Recommended Foods: These are foods that are supposed to be consumed 3-5 times per week. The dosages do not vary throughout a cycle. The week will be reset based the data entered in the Edit Cycle page mentioned below. 
Goal: Develop an app that makes it easy to track daily progress and log the items consumed throughout the day.

Data Storage: All cycle data will be stored in Firebase and will be accessible to all users in the room. This includes access to current and past cycles with logged items. In addition to cycle data, Firebase will also house data related to the current state of the app to propagate to all users- this includes logged items, treatment timers if present, etc. User data will also be stored in Firebase to allow users to have different settings (reminders, treatment food timer). Data in the app should persist through force closes via firebase and local caches until a firebase connection is restored. 

Initial Setup: On first launch, the user should be prompted whether they are setting up for themselves or have a room code. Temporary users will have a room code shared by an admin user. Temporary users are log only and do not have access to change plan settings or history items. They can set their own reminders and treatment timer settings. Amin users will progress through cycle setup, edit item, reminders, treatment timer, before confirming and landing at the home page. 

New Cycle Setup: At the end of a cycle (food challenge date), prompt the user to setup a new cycle. This will take them back to a setup screen to walk through the setup again. The Patient name should autofill, as well as the cycle number should advance from the previous cycle. All items added last cycle should remain and the user can modify/add/delete items and move them to different categories if needed. 

Home Screen:
Home screen with “Patient Name” Plan up top and under that the current cycle number, week and day of the plan. The cycle number, week and day of the plan will be based on the data entered in the “Edit Cycle” page described below. For the week and day calculation, please assume the first week starts as week 1, not week zero. So the date entered in the “Cycle Dosing Start Date” should be Week 1 Day 1 and will progress forward from then until the Food Challenge Date.
Four categories and the items for the current cycle listed under each category.
A checkbox next to each item that the user can check when the item has been consumed.
A progress bar for each recommended food that tracks how many times they have been eaten in that current cycle week (remember that these foods need to be eaten 3-5 times per week). The bar turns green when 3 logs have occurred for the week, and turns red when over 5 logs have occurred.
Two buttons at the bottom of the home screen- one on the left, and one on the right. These buttons will include settings on the right (a gear icon), and Week View on the left. I will describe each button and what they do later. 
The checkboxes will reset at midnight each day, allowing the user to have a fresh start on logging items the next day. The checkboxes should uncheck automatically whether the app is open or not. 

Edit Plan Page- located in settings page: This page will be responsible for all edits made to cycles and items. It will be accessible under the settings page.
Options within the “Edit Plan” page: “Edit Cycle”, “Edit Items”, “Edit Units”
There should be a save button that takes the user back to the “Home Screen”

Edit Cycle page
Patient Name field
“Cycle Number” picker (numbers 1-25)
Date picker for “Cycle Dosing Start Date”
Date picker for “Food Challenge Date”
Save button that take the user back to the “Edit Plan” page

Edit Items page:
This page will always show the four categories and an “add item” button below each category for adding an item. There will be no items added at the first launch of the app. The user will enter items according to the plan.
There should be a save button that takes the user back to the “Edit Plan” page.
Add functionality to allow the user to drag and drop to reorder items within the category they reside, or to move items to a different category. 
When a user clicks into an item in the Treatment Food category, or clicks the “add item” button under the Treatment Food category, they should be taken to the “Add Treatment Food Item” page, as it is specific to treatment foods with extra options for adding.

Edit Units page- located in settings:
A page with all dose units listed. 
Have a button to “Add Unit”, which allows the user to input a unit. If clicked, this takes the user to the “Add Unit” page.
Have a red minus sign associated with each unit that allows the user to delete a unit. Have a confirmation popup before deleting. 
If the user clicks the name of a unit, they are able to edit the name from this page.

Add Item page:
There should be fields for “Item Name” in which the user can type the name of the item.
There should be a dose line in which the user specifies the dose and units. Label this line “Dose”.
The unit picker should be a selector and should list all units within the “Edit Units” page. 
There should be an option at the bottom of the units selector to “Add a Unit”, which takes the user to the “Add Unit from Item List” page.
There should be a save button up top that takes the user back to the “Edit Items” page and displays the newly created Item with dose and units under the correct category. 

Add Unit page
This will contain a text box labeled “Unit” in which the user types a unit. There will be a save button up top to take the user back to the “Edit Units” page where the new unit will display.

Add Unit from Item List page
Exactly the same as the “Add Unit” page except that the save button takes the user back to the “Add Item” page and inputs the newly created unit in the unit selector. 

Add Treatment Food Item page
This page should be very similar to the “Add Item” page. 
The “Item Name” field will still be present and will allow the user to add or edit the name of the item.
There should be a toggle that is labeled “Add Future Week Doses”. By default this should be enabled in the yes position. 
When enabled or in the yes position, the page will display a list of the weeks in the cycle. It will not show weeks that have already past. For example, if we are on week 6 day 4 of a 12 week cycle, this page should show weeks 6-12. 
Under each week, the user will have the same dose options as the “Add Items” page. They should be able to enter a dose and units for each week. If choosing “Add a Unit” from the selector in this page, the user should be taken to the “Add Unit from Treatment Item List” page. 
All weeks are required to be filled out. Once complete, the user can select the save button up top and return to the “Edit Items” page.
If the toggle is switched to off, this assumes the dosing is the same for all the weeks in the cycle. Allow the user to enter in the dose and units. 

Add Unit from Treatment Item List
Exact same as the “Add Unit from Item List” page, except the save button takes the user back to the “Add Treatment Food Item” page. The newly created unit should be chosen in the selector that the user was working in while using the “Add a Unit” feature on the “Add Treatment Food Item” page.  

Reminders Page- located in settings
Enables the user to toggle a daily reminder for each category to remind them to log an item. Have a time picker to allow the user to toggle the reminder on/off and also pick the time of the reminder. 

Treatment Food Timer Page- located in settings
Enables the user to toggle on/off a timer after logging a treatment food. The goal is to space treatment foods 15 minutes apart. So if we have three treatment foods for example, after item 1/3 is logged, a timer would pop up next to the treatment category name in the home view that would count down until the next treatment food can be logged. There should be a notification that fires at the end of the treatment food timer countdown. After item 2/3 is logged, the timer would be called and run again. The timer would not run after item 3/3 is logged, because there are no other remaining treatment foods to be logged. 

History Page- located in settings
Show history by day of all items logged. Show item, category, user, and time it was logged. Allow editing by admin users by clicking the item name and having the ability to delete item, edit time. 

Week View page- button located on Home Screen L corner
Week by week view of items logged and categories. The current day should be highlight yellow and it should default to opening to the current week. 
Have a cycle picker and week picker so users can flip between cycles and weeks to view history.
