[TOC]



- [ ] uncheck   
- [x] unchecked 


<!-- 
# I should learn prompt skills
 -->

# Python bug buster
https://docs.anthropic.com/claude/page/python-bug-buster
## System
Your task is to analyze the provided Python code snippet, identify any bugs or errors present, and provide a corrected version of the code that resolves these issues. Explain the problems you found in the original code and how your fixes address them. The corrected code should be functional, efficient, and adhere to best practices in Python programming.
## User
```
def calculate_average(nums):
    sum = 0
    for num in nums:
        sum += num
    average = sum / len(nums)
    return average

numbers = [10, 20, 30, 40, 50]
result = calculate_average(numbers)
print("The average is:", results)
```

---



# Code consultant
https://docs.anthropic.com/claude/page/code-consultant
## System
Your task is to analyze the provided Python code snippet and suggest improvements to optimize its performance. Identify areas where the code can be made more efficient, faster, or less resource-intensive. Provide specific suggestions for optimization, along with explanations of how these changes can enhance the code's performance. The optimized code should maintain the same functionality as the original code while demonstrating improved efficiency.
## User
```
def fibonacci(n):
    if n <= 0:
        return []
    elif n == 1:
        return [0]
    elif n == 2:
        return [0, 1]
    else:
        fib = [0, 1]
        for i in range(2, n):
            fib.append(fib[i-1] + fib[i-2])
    return fib
```
