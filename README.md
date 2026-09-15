# Role-Based Asset Transaction and Approval Management System

**Course:** Systems Analysis and Design  
**Laboratory:** Laboratory 4 - Section A  
**Development Platform:** GitHub + GitHub Pages + Supabase  

## Project Overview
The existing Laboratory Asset and Service Management System has been enhanced to introduce stronger system controls. This iteration implements multiple user roles, a borrowing-request approval workflow, business rule enforcement across transaction states, and a comprehensive audit trail for critical system actions.

## Live Demo & Repository
- **Live GitHub Pages URL:** [https://smeryl.github.io/lab-asset-system/](https://smeryl.github.io/lab-asset-system/)
- **GitHub Repository URL:** [https://github.com/smeryl/lab-asset-system](https://github.com/smeryl/lab-asset-system)

## Test Accounts
For evaluation purposes, the following accounts have been set up:

| Role | Email | Password |
| :--- | :--- | :--- |
| Admin | `admin@lab.com` | `password123` |
| Laboratory Staff | `staff@lab.com` | `password123` |
| Requester | `request@lab.com` | `password123` |

## Technologies Used
- **Frontend:** HTML5, CSS3, Vanilla JavaScript (ES Modules)
- **Backend / Database:** Supabase (PostgreSQL, Authentication, Row Level Security)
- **Hosting:** GitHub Pages

---

## 1. Required User Roles & Permissions Matrix
Navigation adapts to the logged-in role. Administrators see management and audit functions; staff see operational functions; requesters see only request and history functions.

| Function | Administrator | Laboratory Staff | Requester / Viewer |
| :--- | :---: | :---: | :---: |
| Manage Users | ✅ | ❌ | ❌ |
| Manage Equipment | ✅ | ❌ | ❌ |
| View Equipment | ✅ | ✅ | ✅ |
| Create Borrowing Transaction | ✅ | ✅ | ❌ |
| Submit Borrowing Request | ✅ | ✅ | ✅ |
| Approve/Reject Requests | ✅ | ❌ | ❌ |
| Process Returns | ✅ | ✅ | ❌ |
| Submit Maintenance Requests | ✅ | ✅ | ❌ |
| View Reports | ✅ | ❌ | ❌ |
| View Audit Logs | ✅ | ❌ | ❌ |
| View Own Request Status | ✅ | ✅ | ✅ |

---

## 2. Borrowing Approval Workflow
The system enforces a strict workflow for asset transactions:
`Borrowing Request Submitted` → `Pending` → `Administrator Reviews` → `Approved` / `Rejected`
- If Approved → `Released` → `Returned` → `Closed`
- If Rejected → Request is closed and cannot be released.

**Required statuses implemented:** Pending, Approved, Rejected, Released, Returned, Overdue, Closed.

---

## 3. Business Rules Implemented
These rules are enforced at both the interface (JavaScript) and database levels (RLS + Triggers).

| ID | Business Rule |
| :--- | :--- |
| BR-A4-01 | Only available equipment may be requested. |
| BR-A4-02 | Staff cannot approve their own request. |
| BR-A4-03 | Only Administrator may approve or reject requests. |
| BR-A4-04 | Only Approved requests may be released. |
| BR-A4-05 | Released equipment becomes Borrowed. |
| BR-A4-06 | Returned equipment becomes Available unless damaged. |
| BR-A4-07 | Rejected requests cannot be released. |
| BR-A4-08 | Returned transactions cannot be processed twice. |
| BR-A4-09 | Equipment under Maintenance cannot be borrowed. |
| BR-A4-10 | Sensitive operations must be logged. |

---

## 4. Audit Trail
A comprehensive `audit_logs` table has been implemented to track critical system actions. 

**Table Structure:**
- `id` (BigInt, PK)
- `user_id` (UUID, FK to users)
- `action` (Text)
- `module` (Text)
- `record_id` (BigInt)
- `description` (Text)
- `created_at` (Timestamp)

**Example Log Entry:**
> **User:** Maria Santos  
> **Action:** APPROVED  
> **Module:** Borrowing  
> **Record ID:** 102  
> **Description:** Approved borrowing request for LAP-001

*Audit logs are automatically generated via PostgreSQL triggers on the `borrowing_requests` and `equipment` tables.*

---

## 5. Functional Testing Results

| Test ID | Scenario | Expected Result | Actual Result |
| :--- | :--- | :--- | :--- |
| TC-A4-01 | Viewer attempts to open Admin page | Access denied. | Passed |
| TC-A4-02 | Staff submits request | Request saved as Pending. | Passed |
| TC-A4-03 | Administrator approves request | Status becomes Approved; audit log created. | Passed |
| TC-A4-04 | Administrator rejects request | Status becomes Rejected. | Passed |
| TC-A4-05 | Attempt to release rejected request | Operation blocked. | Passed |
| TC-A4-06 | Release approved equipment | Equipment becomes Borrowed. | Passed |
| TC-A4-07 | Return released equipment | Equipment returns to appropriate status. | Passed |
| TC-A4-08 | Check audit log after approval | Approval entry is visible. | Passed |
| TC-A4-09 | Staff attempts restricted delete | Operation blocked. | Passed |
| TC-A4-10 | Logout and open protected page | Redirected to login / access denied. | Passed |

---
---

## 6. Setup Instructions (Local Development)
1. Clone the repository: `git clone https://github.com/smeryl/lab-asset-system.git`
2. Create a project on [Supabase](https://supabase.com).
3. Run the SQL scripts found in the `/sql` folder in the Supabase SQL Editor to create tables, RLS policies, and triggers.
4. Open `js/supabaseClient.js` and insert your Supabase Project URL and `anon` public key.
5. Serve the project locally using VS Code's Live Server extension or `python -m http.server 5500`.
6. Access the app at `http://localhost:5500/login.html`.

